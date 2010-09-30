-----------------------------------------------------------------------------
--  Project      : Diamond FOFB Communication Controller
--  Filename     : fofb_cc_top.vhd
--  Purpose      : FOFB Communication Controller (CC) top level file
--  Author       : Isa S. Uzun
-----------------------------------------------------------------------------
--  Copyright (c) 2007 Diamond Light Source Ltd.
--  All rights reserved.
-----------------------------------------------------------------------------
--  Description: Communication Controller top level module.
-----------------------------------------------------------------------------
--  Limitations & Assumptions:
-----------------------------------------------------------------------------
--  Known Errors: This design is still under test. Please send any bug
--reports to isa.uzun@diamond.ac.uk
-----------------------------------------------------------------------------
--  TO DO List:
-----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.fofb_cc_pkg.all;-- DLS FOFB package

-----------------------------------------------
--  Entity declaration
-----------------------------------------------
entity fofb_cc_top is
    generic (
        -- Default node ID 0-255
        ID                      : integer := 255;
        -- FPGA Device
        DEVICE                  : device_t := BPM;
        USE_DCM                 : boolean := true;
        SIM_GTPRESET_SPEEDUP    : integer := 0;
        -- Extended FAI interface for FOFB
        EXTENDED_CONF_BUF       : boolean := false;
        -- Absolute or Difference position data
        TX_BPM_POS_ABS          : boolean := true;
        -- MGT Interface Parameters
        LANE_COUNT              : integer := 4;
        TX_IDLE_NUM             : integer := 16;
        RX_IDLE_NUM             : integer := 13;
        SEND_ID_NUM             : integer := 14
    );
    port (
        -- differential MGT/GTP clock inputs
        refclk_p_i              : in  std_logic;
        refclk_n_i              : in  std_logic;
        -- clock and reset interface
        adcclk_i                : in std_logic;
        adcreset_i              : in std_logic;
        sysclk_i                : in std_logic;
        -- fast acquisition data interface
        fai_fa_block_start_i    : in std_logic;
        fai_fa_data_valid_i     : in std_logic;
        fai_fa_d_i              : in std_logic_vector(15 downto 0);
        -- FOFB communication controller configuration interface
        fai_cfg_a_o             : out std_logic_vector(10 downto 0);
        fai_cfg_d_o             : out std_logic_vector(31 downto 0);
        fai_cfg_d_i             : in  std_logic_vector(31 downto 0);
        fai_cfg_we_o            : out std_logic;
        fai_cfg_clk_o           : out std_logic;
        fai_cfg_val_i           : in  std_logic_vector(31 downto 0);
        -- serial I/Os for eight RocketIOs on the Libera 
        fai_rio_rdp_i           : in  std_logic_vector(LANE_COUNT-1 downto 0);
        fai_rio_rdn_i           : in  std_logic_vector(LANE_COUNT-1 downto 0);
        fai_rio_tdp_o           : out std_logic_vector(LANE_COUNT-1 downto 0);
        fai_rio_tdn_o           : out std_logic_vector(LANE_COUNT-1 downto 0);
        fai_rio_tdis_o          : out std_logic_vector(LANE_COUNT-1 downto 0);
        -- inverse response matrix coefficient buffer i/o
        coeff_x_addr_i          : in  std_logic_vector(7 downto 0);
        coeff_x_dat_o           : out std_logic_vector(31 downto 0);
        coeff_y_addr_i          : in  std_logic_vector(7 downto 0);
        coeff_y_dat_o           : out std_logic_vector(31 downto 0);
        -- Higher-level integration interface (PMC, SNIFFER_V5)
        xy_buf_addr_i           : in  std_logic_vector(9 downto 0);
        xy_buf_dat_o            : out std_logic_vector(63 downto 0);
        timeframe_end_rise_o    : out std_logic;
        timeframe_start_o       : out std_logic;
        fofb_watchdog_i         : in  std_logic_vector(31 downto 0);
        fofb_event_i            : in  std_logic_vector(31 downto 0);
        fofb_process_time_o     : out std_logic_vector(15 downto 0);
        fofb_bpm_count_o        : out std_logic_vector(7 downto 0);
        fofb_dma_ok_i           : in  std_logic;
        fofb_node_mask_o        : out std_logic_vector(NodeNum-1 downto 0);
        fofb_rxlink_up_o        : out std_logic;
        fofb_rxlink_partner_o   : out std_logic_vector(9 downto 0);
        fofb_timestamp_val_o    : out std_logic_vector(31 downto 0);
        -- PBPM position data interface
        pbpm_xpos_val_i         : in  std_logic_vector(31 downto 0);
        pbpm_ypos_val_i         : in  std_logic_vector(31 downto 0)
);
end fofb_cc_top;

architecture structural of fofb_cc_top is

--
-- Coregen RX and TX FIFO component declarations
--
component fofb_cc_rx_fifo
    port (
        rd_en                   : in  std_logic;
        wr_en                   : in  std_logic;
        full                    : out std_logic;
        empty                   : out std_logic;
        wr_clk                  : in  std_logic;
        rst                     : in  std_logic;
        rd_clk                  : in  std_logic;
        dout                    : out std_logic_vector(127 downto 0);
        din                     : in  std_logic_vector(15 downto 0)
    );
end component;

component fofb_cc_tx_fifo
    port (
        rd_en                   : in  std_logic;
        wr_en                   : in  std_logic;
        full                    : out std_logic;
        empty                   : out std_logic;
        wr_clk                  : in  std_logic;
        rst                     : in  std_logic;
        rd_clk                  : in  std_logic;
        dout                    : out std_logic_vector(15 downto 0);
        din                     : in  std_logic_vector(127 downto 0)
    );
end component;

--
-- Communication Controller has to be compiled with ISE 7.1i and
-- it does not support Virtex-5 devices. And > ISE 11.1i versions 
-- do not support Virtex2Pro devices.
--
component fofb_cc_mgt_if
generic (
    -- CC Design selection parameters
    DEVICE                  : device_t := BPM;
    LaneCount               : integer := 4;
    TX_IDLE_NUM             : natural := 16;
    RX_IDLE_NUM             : natural := 13;
    SEND_ID_NUM             : natural := 14
);
port (
    -- clocks and resets
    refclk_i                : in  std_logic;
    userclk_i               : in  std_logic;
    mgtreset_i              : in  std_logic;

    rxn_i                   : in  std_logic_vector(LANE_COUNT-1 downto 0);
    rxp_i                   : in  std_logic_vector(LANE_COUNT-1 downto 0);
    txn_o                   : out std_logic_vector(LANE_COUNT-1 downto 0);
    txp_o                   : out std_logic_vector(LANE_COUNT-1 downto 0);

    -- time frame sync
    timeframe_start_i       : in  std_logic;
    timeframe_end_i         : in  std_logic;
    timeframe_val_i         : in  std_logic_vector(15 downto 0);
    bpmid_i                 : in  std_logic_vector(7 downto 0);

    -- mgt configuration 
    powerdown_i             : in  std_logic_vector(3 downto 0);
    loopback_i              : in  std_logic_vector(7 downto 0);

    -- status information
    linksup_o               : out std_logic_vector(7 downto 0);
    frameerror_cnt_o        : inout std_logic_2d_16(3 downto 0); 
    softerror_cnt_o         : inout std_logic_2d_16(3 downto 0); 
    harderror_cnt_o         : inout std_logic_2d_16(3 downto 0); 
    txpck_cnt_o             : out std_logic_2d_16(3 downto 0);
    rxpck_cnt_o             : out std_logic_2d_16(3 downto 0);

    -- network information
    tfs_bit_o               : out std_logic_vector(3 downto 0);
    link_partner_o          : out std_logic_2d_10(3 downto 0);
    pmc_timeframe_val_o     : out std_logic_2d_16(3 downto 0);
    pmc_timestamp_val_o     : out std_logic_2d_32(3 downto 0);

    -- tx/rx state machine status for reset operation
    tx_sm_busy_o            : out std_logic_vector(LANE_COUNT-1 downto 0);
    rx_sm_busy_o            : out std_logic_vector(LANE_COUNT-1 downto 0);

    -- TX FIFO interface
    tx_dat_i                : in  std_logic_2d_16(LANE_COUNT-1 downto 0);
    txf_empty_i             : in  std_logic_vector(LANE_COUNT-1 downto 0);
    txf_rd_en_o             : out std_logic_vector(LANE_COUNT-1 downto 0);

    -- RX FIFO interface
    rxf_full_i              : in  std_logic_vector(LANE_COUNT-1 downto 0);
    rx_dat_o                : out std_logic_2d_16(LANE_COUNT-1 downto 0);
    rx_dat_val_o            : out std_logic_vector(LANE_COUNT-1 downto 0)

);
end component;

component fofb_cc_gtp_if
generic (
    -- CC Design selection parameters
    LaneCount               : integer := 2;
    TX_IDLE_NUM             : natural := 16;
    RX_IDLE_NUM             : natural := 13;
    SEND_ID_NUM             : natural := 14;
    -- Simulation parameters
    SIM_GTPRESET_SPEEDUP    : integer   := 0
);
port (
    -- clocks and resets
    refclk_i                : in  std_logic;
    mgtreset_i              : in  std_logic;
    -- system interface
    gtreset_i               : in  std_logic;
    txoutclk_o              : out std_logic;
    plllkdet_o              : out std_logic;
    txusrclk_i              : in  std_logic;
    txusrclk2_i             : in  std_logic;
    -- RocketIO·
    rxn_i                   : in  std_logic_vector(LANE_COUNT-1 downto 0);
    rxp_i                   : in  std_logic_vector(LANE_COUNT-1 downto 0);
    txn_o                   : out std_logic_vector(LANE_COUNT-1 downto 0);
    txp_o                   : out std_logic_vector(LANE_COUNT-1 downto 0);
    -- time frame sync
    timeframe_start_i       : in  std_logic;
    timeframe_end_i         : in  std_logic;
    timeframe_val_i         : in  std_logic_vector(15 downto 0);
    bpmid_i                 : in  std_logic_vector(7 downto 0);
    -- mgt configuration·
    powerdown_i             : in  std_logic_vector(3 downto 0);
    loopback_i              : in  std_logic_vector(7 downto 0);
    -- status information
    linksup_o               : out std_logic_vector(7 downto 0);
    frameerror_cnt_o        : inout std_logic_2d_16(3 downto 0); 
    softerror_cnt_o         : inout std_logic_2d_16(3 downto 0);
    harderror_cnt_o         : inout std_logic_2d_16(3 downto 0);
    txpck_cnt_o             : out std_logic_2d_16(3 downto 0);
    rxpck_cnt_o             : out std_logic_2d_16(3 downto 0);
    -- network information
    tfs_bit_o               : out std_logic_vector(3 downto 0);
    link_partner_o          : out std_logic_2d_10(3 downto 0);
    pmc_timeframe_val_o     : out std_logic_2d_16(3 downto 0);
    pmc_timestamp_val_o     : out std_logic_2d_32(3 downto 0);
    -- tx/rx state machine status for reset operation
    tx_sm_busy_o            : out std_logic_vector(LANE_COUNT-1 downto 0);
    rx_sm_busy_o            : out std_logic_vector(LANE_COUNT-1 downto 0);
    -- TX FIFO interface
    tx_dat_i                : in  std_logic_2d_16(LANE_COUNT-1 downto 0);
    txf_empty_i             : in  std_logic_vector(LANE_COUNT-1 downto 0);
    txf_rd_en_o             : out std_logic_vector(LANE_COUNT-1 downto 0);
    -- RX FIFO interface
    rxf_full_i              : in  std_logic_vector(LANE_COUNT-1 downto 0);
    rx_dat_o                : out std_logic_2d_16(LANE_COUNT-1 downto 0);
    rx_dat_val_o            : out std_logic_vector(LANE_COUNT-1 downto 0)
);
end component;

component fofb_cc_gtx_if
generic (
    -- CC Design selection parameters
    LaneCount               : integer := 2;
    TX_IDLE_NUM             : natural := 16;
    RX_IDLE_NUM             : natural := 13;
    SEND_ID_NUM             : natural := 14;
    -- Simulation parameters
    SIM_GTPRESET_SPEEDUP    : integer   := 0
);
port (
    -- clocks and resets
    refclk_i                : in  std_logic;
    mgtreset_i              : in  std_logic;
    -- system interface
    gtreset_i               : in  std_logic;
    txoutclk_o              : out std_logic;
    plllkdet_o              : out std_logic;
    txusrclk_i              : in  std_logic;
    txusrclk2_i             : in  std_logic;
    -- RocketIO·
    rxn_i                   : in  std_logic_vector(LANE_COUNT-1 downto 0);
    rxp_i                   : in  std_logic_vector(LANE_COUNT-1 downto 0);
    txn_o                   : out std_logic_vector(LANE_COUNT-1 downto 0);
    txp_o                   : out std_logic_vector(LANE_COUNT-1 downto 0);
    -- time frame sync
    timeframe_start_i       : in  std_logic;
    timeframe_end_i         : in  std_logic;
    timeframe_val_i         : in  std_logic_vector(15 downto 0);
    bpmid_i                 : in  std_logic_vector(7 downto 0);
    -- mgt configuration·
    powerdown_i             : in  std_logic_vector(3 downto 0);
    loopback_i              : in  std_logic_vector(7 downto 0);
    -- status information
    linksup_o               : out std_logic_vector(7 downto 0);
    frameerror_cnt_o        : inout std_logic_2d_16(3 downto 0); 
    softerror_cnt_o         : inout std_logic_2d_16(3 downto 0);
    harderror_cnt_o         : inout std_logic_2d_16(3 downto 0);
    txpck_cnt_o             : out std_logic_2d_16(3 downto 0);
    rxpck_cnt_o             : out std_logic_2d_16(3 downto 0);
    -- network information
    tfs_bit_o               : out std_logic_vector(3 downto 0);
    link_partner_o          : out std_logic_2d_10(3 downto 0);
    pmc_timeframe_val_o     : out std_logic_2d_16(3 downto 0);
    pmc_timestamp_val_o     : out std_logic_2d_32(3 downto 0);
    -- tx/rx state machine status for reset operation
    tx_sm_busy_o            : out std_logic_vector(LANE_COUNT-1 downto 0);
    rx_sm_busy_o            : out std_logic_vector(LANE_COUNT-1 downto 0);
    -- TX FIFO interface
    tx_dat_i                : in  std_logic_2d_16(LANE_COUNT-1 downto 0);
    txf_empty_i             : in  std_logic_vector(LANE_COUNT-1 downto 0);
    txf_rd_en_o             : out std_logic_vector(LANE_COUNT-1 downto 0);
    -- RX FIFO interface
    rxf_full_i              : in  std_logic_vector(LANE_COUNT-1 downto 0);
    rx_dat_o                : out std_logic_2d_16(LANE_COUNT-1 downto 0);
    rx_dat_val_o            : out std_logic_vector(LANE_COUNT-1 downto 0)
);
end component;

-----------------------------------------
-- Signal declarations
-----------------------------------------
--  tx fifo
signal txf_din              : std_logic_vector((32*PacketSize-1) downto 0);
signal txf_wr_en            : std_logic_vector(LANE_COUNT-1 downto 0);
signal txf_rd_en            : std_logic_vector(LANE_COUNT-1 downto 0);
signal txf_empty            : std_logic_vector(LANE_COUNT-1 downto 0);
signal txf_dout             : std_logic_2d_16(LANE_COUNT-1 downto 0);
signal txf_full             : std_logic_vector(LANE_COUNT-1 downto 0);
-- rx fifo
signal rxf_din              : std_logic_2d_16(LANE_COUNT-1 downto 0);
signal rxf_dout             : std_logic_2d_128(LANE_COUNT-1 downto 0);
signal rxf_wr_en            : std_logic_vector(LANE_COUNT-1 downto 0);
signal rxf_rd_en            : std_logic_vector(LANE_COUNT-1 downto 0);
signal rxf_empty            : std_logic_vector(LANE_COUNT-1 downto 0);
signal rxf_empty_n          : std_logic_vector(LANE_COUNT-1 downto 0);
signal rxf_full             : std_logic_vector(LANE_COUNT-1 downto 0);
-- frame status 
signal timeframe_end        : std_logic;
signal timeframe_count      : std_logic_vector(31 downto 0) := (others=>'0');
signal link_partners        : std_logic_2d_10(3 downto 0);
signal timeframe_len        : std_logic_vector(15 downto 0);
-- channel status signals
signal linkup               : std_logic_vector(7 downto 0);
signal rx_linkup            : std_logic_vector(3 downto 0);
signal tx_linkup            : std_logic_vector(3 downto 0);
-- system reset
signal rx_fifo_rst          : std_logic_vector(LANE_COUNT-1 downto 0); 
signal tx_fifo_rst          : std_logic_vector(LANE_COUNT-1 downto 0); 
-- arbmux module connections
signal arbmux_dout          : std_logic_vector((32*PacketSize-1) downto 0);
signal arbmux_dout_rdy      : std_logic;
-- configuration signals
signal bpm_id               : std_logic_vector(9 downto 0);
signal mgt_powerdown        : std_logic_vector(3 downto 0);
signal mgt_loopback         : std_logic_vector(7 downto 0);
-- time frame start signals
signal bpm_timeframe_start  : std_logic := '0';
signal pmc_timeframe_start  : std_logic_vector(3 downto 0);
signal timeframe_start      : std_logic := '0';
-- own bpm position
signal bpm_own_xpos         : std_logic_vector(31 downto 0);
signal bpm_own_ypos         : std_logic_vector(31 downto 0);
-- status info
signal tx_fsm_busy          : std_logic_vector(LANE_COUNT-1 downto 0);
signal rx_fsm_busy          : std_logic_vector(LANE_COUNT-1 downto 0);
signal harderror_cnt        : std_logic_2d_16(3 downto 0);
signal softerror_cnt        : std_logic_2d_16(3 downto 0);
signal frameerror_cnt       : std_logic_2d_16(3 downto 0);
signal rxpck_count          : std_logic_2d_16(3 downto 0);
signal txpck_count          : std_logic_2d_16(3 downto 0);
signal bpm_count            : std_logic_vector(7 downto 0);
signal fodprocess_time      : std_logic_vector(15 downto 0);
signal link_up_i            : std_logic_vector(7 downto 0);
signal golden_orb_x         : std_logic_vector(31 downto 0);
signal golden_orb_y         : std_logic_vector(31 downto 0);
signal pmc_timeframe_val    : std_logic_2d_16(3 downto 0);
signal pmc_timestamp_val    : std_logic_2d_32(3 downto 0);
signal timestamp_val        : std_logic_vector(31 downto 0);

signal refclk               : std_logic;
signal sysreset             : std_logic;
signal adcreset             : std_logic;
signal txoutclk             : std_logic;
signal plllkdet             : std_logic;
signal userclk              : std_logic;
signal userclk_2x           : std_logic;
signal mgtreset             : std_logic;
signal gtreset              : std_logic;

signal fai_cfg_act_part     : std_logic;
signal fofb_pos_datsel      : std_logic;
signal fofb_cc_enable       : std_logic;

signal tied_to_ground       : std_logic;

begin

-- Static
tied_to_ground <= '0';

----------------------------------------------
-- Link status information to higher-level
----------------------------------------------
fofb_rxlink_up_o      <= rx_linkup(0);
fofb_rxlink_partner_o <= link_partners(0);
fofb_process_time_o   <= fodprocess_time;
fofb_bpm_count_o      <= bpm_count;
fofb_timestamp_val_o  <= timestamp_val;

fai_cfg_clk_o <= userclk;

----------------------------------------------
-- re-arrange rx and tx channel up outputs
----------------------------------------------
rx_linkup <= linkup(7) & linkup(5) & linkup(3) & linkup(1);
tx_linkup <= linkup(6) & linkup(4) & linkup(2) & linkup(0);
link_up_i <= tx_linkup & rx_linkup;

----------------------------------------------
-- enable all mgt transceivers on digital board
----------------------------------------------
fai_rio_tdis_o <= (others => '0');

----------------------------------------------------------------------
-- timeframe pulses to top level
----------------------------------------------------------------------
timeframe_start_exp : entity work.fofb_cc_puls_exp
port map (
    mgtclk_i                => userclk,
    mgtreset_i              => sysreset,
    short_pulse_i           => timeframe_start,
    long_pulse_o            => timeframe_start_o
);

----------------------------------------------------------------------
-- reset signals: fai_cfg_val(3) from user is used as user reset
----------------------------------------------------------------------
--
--
fofb_cc_enable <= fai_cfg_val_i(3);
fofb_pos_datsel <= fai_cfg_val_i(1);
fai_cfg_act_part <= fai_cfg_val_i(0);

sysreset <= mgtreset or not fofb_cc_enable;
adcreset <= adcreset_i; -- or not fai_cfg_val_i(0);

----------------------------------------------------------------------
-- MGT reference clocks, user clocks and reset interface
---------------------------------------------------------------------- 
fofb_cc_clk_if : entity work.fofb_cc_clk_if
generic map (
    -- FPGA Device
    DEVICE                  => DEVICE,
    USE_DCM                 => USE_DCM
)
port map (
    refclk_n_i              => refclk_n_i,
    refclk_p_i              => refclk_p_i,

    refclk_o                => refclk,
    mgtreset_o              => mgtreset,
    gtreset_o               => gtreset,

    txoutclk_i              => txoutclk,
    plllkdet_i              => plllkdet,

    userclk_o               => userclk,
    userclk_2x_o            => userclk_2x
);

----------------------------------------------
-- Generate N  Virtex-2Pro MGT Channels
----------------------------------------------
MGT_IF_GEN : if (DEVICE /= SNIFFER_V5 and DEVICE /= SNIFFER_V6) generate
MGT_LANE: fofb_cc_mgt_if
generic map (
    DEVICE                  => DEVICE,
    LaneCount               => LANE_COUNT,
    TX_IDLE_NUM             => TX_IDLE_NUM,
    RX_IDLE_NUM             => RX_IDLE_NUM,
    SEND_ID_NUM             => SEND_ID_NUM
)
port map (
    refclk_i                => refclk,
    mgtreset_i              => sysreset,
    userclk_i               => userclk,

    rxn_i                   => fai_rio_rdn_i,
    rxp_i                   => fai_rio_rdp_i,
    txn_o                   => fai_rio_tdn_o,
    txp_o                   => fai_rio_tdp_o,

    timeframe_start_i       => timeframe_start,
    timeframe_end_i         => timeframe_end,
    timeframe_val_i         => timeframe_count(15 downto 0),
    bpmid_i                 => bpm_id(7 downto 0),

    powerdown_i             => mgt_powerdown,
    loopback_i              => mgt_loopback,
    linksup_o               => linkup,
    harderror_cnt_o         => harderror_cnt,
    softerror_cnt_o         => softerror_cnt,
    frameerror_cnt_o        => frameerror_cnt,

    tx_sm_busy_o            => tx_fsm_busy,
    rx_sm_busy_o            => rx_fsm_busy,

    tfs_bit_o               => pmc_timeframe_start,
    link_partner_o          => link_partners,
    pmc_timeframe_val_o     => pmc_timeframe_val,
    pmc_timestamp_val_o     => pmc_timestamp_val,

    txpck_cnt_o             => txpck_count,
    rxpck_cnt_o             => rxpck_count,

    tx_dat_i                => txf_dout,
    txf_empty_i             => txf_empty,
    txf_rd_en_o             => txf_rd_en,

    rxf_full_i              => rxf_full,
    rx_dat_o                => rxf_din,
    rx_dat_val_o            => rxf_wr_en
);
end generate;

----------------------------------------------------------------------
-- Generate N Virtex-5 GTP channels
----------------------------------------------------------------------
GTP_IF_GEN : if (DEVICE = SNIFFER_V5) generate
GTP_IF: fofb_cc_gtp_if
generic map (
    LaneCount               => LANE_COUNT,
    TX_IDLE_NUM             => TX_IDLE_NUM,
    RX_IDLE_NUM             => RX_IDLE_NUM,
    SEND_ID_NUM             => SEND_ID_NUM,
    SIM_GTPRESET_SPEEDUP    => SIM_GTPRESET_SPEEDUP
)
port map (
    refclk_i                => refclk,
    mgtreset_i              => sysreset,
    gtreset_i               => gtreset,
    txoutclk_o              => txoutclk,
    plllkdet_o              => plllkdet,
    txusrclk_i              => userclk_2x,
    txusrclk2_i             => userclk,

    rxn_i                   => fai_rio_rdn_i,
    rxp_i                   => fai_rio_rdp_i,
    txn_o                   => fai_rio_tdn_o,
    txp_o                   => fai_rio_tdp_o,

    timeframe_start_i       => timeframe_start,
    timeframe_end_i         => timeframe_end,
    timeframe_val_i         => timeframe_count(15 downto 0),
    bpmid_i                 => bpm_id(7 downto 0),

    powerdown_i             => mgt_powerdown,
    loopback_i              => mgt_loopback,
    linksup_o               => linkup,
    harderror_cnt_o         => harderror_cnt,
    softerror_cnt_o         => softerror_cnt,
    frameerror_cnt_o        => frameerror_cnt,

    tx_sm_busy_o            => tx_fsm_busy,
    rx_sm_busy_o            => rx_fsm_busy,

    tfs_bit_o               => pmc_timeframe_start,
    link_partner_o          => link_partners,
    pmc_timeframe_val_o     => pmc_timeframe_val,
    pmc_timestamp_val_o     => pmc_timestamp_val,


    txpck_cnt_o             => txpck_count,
    rxpck_cnt_o             => rxpck_count,

    tx_dat_i                => txf_dout,
    txf_empty_i             => txf_empty,
    txf_rd_en_o             => txf_rd_en,

    rxf_full_i              => rxf_full,
    rx_dat_o                => rxf_din,
    rx_dat_val_o            => rxf_wr_en
);
end generate;

----------------------------------------------------------------------
-- Generate N Virtex-6 GTX channels
----------------------------------------------------------------------
GTX_IF_GEN : if (DEVICE = SNIFFER_V6) generate
GTX_IF: fofb_cc_gtx_if
generic map (
    LaneCount               => LANE_COUNT,
    TX_IDLE_NUM             => TX_IDLE_NUM,
    RX_IDLE_NUM             => RX_IDLE_NUM,
    SEND_ID_NUM             => SEND_ID_NUM,
    SIM_GTPRESET_SPEEDUP    => SIM_GTPRESET_SPEEDUP
)
port map (
    refclk_i                => refclk,
    mgtreset_i              => sysreset,
    gtreset_i               => gtreset,
    txoutclk_o              => txoutclk,
    plllkdet_o              => plllkdet,
    txusrclk_i              => tied_to_ground,
    txusrclk2_i             => userclk,

    rxn_i                   => fai_rio_rdn_i,
    rxp_i                   => fai_rio_rdp_i,
    txn_o                   => fai_rio_tdn_o,
    txp_o                   => fai_rio_tdp_o,

    timeframe_start_i       => timeframe_start,
    timeframe_end_i         => timeframe_end,
    timeframe_val_i         => timeframe_count(15 downto 0),
    bpmid_i                 => bpm_id(7 downto 0),

    powerdown_i             => mgt_powerdown,
    loopback_i              => mgt_loopback,
    linksup_o               => linkup,
    harderror_cnt_o         => harderror_cnt,
    softerror_cnt_o         => softerror_cnt,
    frameerror_cnt_o        => frameerror_cnt,

    tx_sm_busy_o            => tx_fsm_busy,
    rx_sm_busy_o            => rx_fsm_busy,

    tfs_bit_o               => pmc_timeframe_start,
    link_partner_o          => link_partners,
    pmc_timeframe_val_o     => pmc_timeframe_val,
    pmc_timestamp_val_o     => pmc_timestamp_val,


    txpck_cnt_o             => txpck_count,
    rxpck_cnt_o             => rxpck_count,

    tx_dat_i                => txf_dout,
    txf_empty_i             => txf_empty,
    txf_rd_en_o             => txf_rd_en,

    rxf_full_i              => rxf_full,
    rx_dat_o                => rxf_din,
    rx_dat_val_o            => rxf_wr_en
);
end generate;


----------------------------------------------
-- fifo reset module. fifos are flushed at the end
-- of each time rame.
----------------------------------------------
fifo_reset: for N in 0 to (LANE_COUNT - 1) generate
fofb_cc_fifo_rst : entity work.fofb_cc_fifo_rst
port map(
    mgtclk_i                => userclk,
    mgtreset_i              => sysreset,
    tx_linkup_i             => tx_linkup(N),
    rx_linkup_i             => rx_linkup(N),
    timeframe_end_i         => timeframe_end,
    tx_sm_busy_i            => tx_fsm_busy(N),
    rx_sm_busy_i            => rx_fsm_busy(N),
    txfifo_reset_o          => tx_fifo_rst(N),
    rxfifo_reset_o          => rx_fifo_rst(N)
);
end generate;   

----------------------------------------------
-- asymetrical rx fifo generation for each mgt channel 
-- 16-bit input/128-bit output
----------------------------------------------
RX_FIFO_GEN: for N in 0 to (LANE_COUNT - 1) generate
fofb_cc_rx_fifo_i : fofb_cc_rx_fifo
port map (
    din                     => rxf_din(N),
    rd_clk                  => userclk,
    rd_en                   => rxf_rd_en(N),
    rst                     => rx_fifo_rst(N),
    wr_clk                  => userclk,
    wr_en                   => rxf_wr_en(N),
    dout                    => rxf_dout(N),
    empty                   => rxf_empty(N),
    full                    => rxf_full(N)
);
end generate;

----------------------------------------------
-- cc input buffer arbiter. inputs are connected to
-- rx fifo.
----------------------------------------------
fofb_cc_arbmux : entity work.fofb_cc_arbmux
generic map (
    LaneCount               => LANE_COUNT
)
port map (
    mgt_clk                 => userclk,
    mgt_rst                 => sysreset,
    data_in                 => rxf_dout,
    data_in_rdy             => rxf_empty_n,
    rx_fifo_rd_en           => rxf_rd_en,
    channel_up              => rx_linkup(LANE_COUNT-1 downto 0),
    data_out                => arbmux_dout,
    data_out_rdy            => arbmux_dout_rdy,
    timeframe_start_i       => timeframe_start,
    timeframe_end_i         => timeframe_end
);

rxf_empty_n <= not rxf_empty;

-------------------------------------------------
-- CC forward or discard (fod) module
-------------------------------------------------
fofb_cc_fod : entity work.fofb_cc_fod
generic map (
    DEVICE                  => DEVICE,
    LaneCount               => LANE_COUNT
)
port map (
    mgtclk_i                => userclk,
    sysclk_i                => sysclk_i,
    mgtreset_i              => sysreset,
    timeframe_start_i       => timeframe_start ,
    linksup_i               => tx_linkup(LANE_COUNT-1 downto 0),
    fod_dat_i               => arbmux_dout,
    fod_dat_val_i           => arbmux_dout_rdy,
    fod_dat_o               => txf_din,
    fod_dat_val_o           => txf_wr_en,
    timeframe_val_i         => timeframe_count,
    timeframe_end_i         => timeframe_end,
    timeframe_end_rise_o    => timeframe_end_rise_o,
    bpm_x_pos_i             => bpm_own_xpos,
    bpm_y_pos_i             => bpm_own_ypos,
    timestamp_val_i         => timestamp_val,
    pos_datsel_i            => fofb_pos_datsel,
    txf_full_i              => txf_full,
    bpmid_i                 => bpm_id,
    xy_buf_dout_o           => xy_buf_dat_o,
    xy_buf_addr_i           => xy_buf_addr_i,
    fodprocess_time_o       => fodprocess_time,
    bpm_count_o             => bpm_count,
    golden_orb_x_i          => golden_orb_x,
    golden_orb_y_i          => golden_orb_y,
    fofb_watchdog_i         => fofb_watchdog_i,
    fofb_event_i            => fofb_event_i,
    fofb_dma_ok_i           => fofb_dma_ok_i,
    fofb_node_mask_o        => fofb_node_mask_o,
    pbpm_xpos_val_i         => pbpm_xpos_val_i,
    pbpm_ypos_val_i         => pbpm_ypos_val_i
);

-------------------------------------------------
-- tx fifo generation for each mgt channel 
-- 128-bit input/16-bit output
-------------------------------------------------
TX_FIFO_GEN: for N in 0 to (LANE_COUNT - 1) generate
fofb_cc_tx_fifo_i : fofb_cc_tx_fifo
port map (
    din                     => txf_din,
    wr_clk                  => userclk,
    rd_clk                  => userclk,
    rd_en                   => txf_rd_en(N),  
    rst                     => tx_fifo_rst(N),
    wr_en                   => txf_wr_en(N),
    dout                    => txf_dout(N),
    empty                   => txf_empty(N),
    full                    => txf_full(N)
);
end generate;

----------------------------------------------
-- Configuration interface module
----------------------------------------------
fofb_cc_cfg_if : entity work.fofb_cc_cfg_if
generic map (
    ID                      => ID,
    EXTENDED_CONF_BUF       => EXTENDED_CONF_BUF
)
port map(
    mgtclk_i                => userclk,
    mgtreset_i              => mgtreset,
    fai_cfg_act_part_i      => fai_cfg_act_part,
    fai_cfg_a_o             => fai_cfg_a_o,
    fai_cfg_do_o            => fai_cfg_d_o,
    fai_cfg_di_i            => fai_cfg_d_i,
    fai_cfg_we_o            => fai_cfg_we_o,
    bpmid_o                 => bpm_id,
    timeframe_len_o         => timeframe_len,
    powerdown_o             => mgt_powerdown,
    loopback_o              => mgt_loopback,
    pmc_heart_beat_i        => X"00000000",
    link_partners_i         => link_partners,
    link_up_i               => link_up_i,
    timeframe_cnt_i         => timeframe_count(15 downto 0),
    harderror_cnt_i         => harderror_cnt,
    softerror_cnt_i         => softerror_cnt,
    frameerror_cnt_i        => frameerror_cnt,
    rxpck_cnt_i             => rxpck_count,
    txpck_cnt_i             => txpck_count,
    bpmcount_i              => bpm_count,
    fodprocess_time_i       => fodprocess_time,
    coeff_x_addr_i          => coeff_x_addr_i,
    coeff_x_dat_o           => coeff_x_dat_o, 
    coeff_y_addr_i          => coeff_y_addr_i,
    coeff_y_dat_o           => coeff_y_dat_o,
    golden_x_orb_o          => golden_orb_x,
    golden_y_orb_o          => golden_orb_y,
    timeframe_end_i         => timeframe_end,
    fai_cfg_val_i           => fai_cfg_val_i
);

----------------------------------------------
-- fa interface module, removed by synthesizer for PMC
----------------------------------------------
fofb_cc_fa_intf : entity work.fofb_cc_fa_intf
port map( 
    mgt_clk                 => userclk,
    adc_clk                 => adcclk_i,
    adc_rst                 => adcreset,
    mgt_rst                 => sysreset, 
    fa_block_start          => fai_fa_block_start_i,
    fa_data_valid           => fai_fa_data_valid_i,
    fa_data                 => fai_fa_d_i,
    time_frame_start        => bpm_timeframe_start,
    bpm_cc_x_pos            => bpm_own_xpos,
    bpm_cc_y_pos            => bpm_own_ypos
);

----------------------------------------------
-- Control module for tfs inputs from libera and mgts
----------------------------------------------
fofb_cc_frame_cntrl : entity work.fofb_cc_frame_cntrl
generic map (
    DEVICE                  => DEVICE,
    LaneCount               => LANE_COUNT
)
port map(
    mgtclk_i                => userclk,
    mgtreset_i              => sysreset,
    tfs_bpm_i               => bpm_timeframe_start,
    tfs_pmc_i               => pmc_timeframe_start,
    timeframe_len_i         => timeframe_len,
    timeframe_start_o       => timeframe_start,
    timeframe_end_o         => timeframe_end,
    timeframe_val_o         => timeframe_count,
    timestamp_val_o         => timestamp_val,
    pmc_timeframe_val_i     => pmc_timeframe_val,
    pmc_timestamp_val_i     => pmc_timestamp_val
);

end structural;