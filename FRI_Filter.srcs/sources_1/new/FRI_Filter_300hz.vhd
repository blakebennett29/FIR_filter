library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Top-level entity (rename ports to match your board pins)
entity TOP is
    port (
        -- system input clock & reset
        clk_in      : in  std_logic; --100mhz
        resetn_in   : in  std_logic; --u18 button

        -- audio master clock from codec / clocking
        --aud_mclk    : in  std_logic; --24.573

        -- I2S pins to/from codec (just to keep things from being optimized away)
        i2s_rx_sdata : in  std_logic; --channels 1,2
        i2s_rx_lrclk : out std_logic; --determended by i2s core
        i2s_rx_sclk  : out std_logic; --bit clock determended by i2s core
        i2s_rx_mclk  : out  std_logic; -- 24.576Mhz clk
        
        i2s_tx_sdata : out std_logic; --to out data pin on pmod
        i2s_tx_lrclk : out std_logic; --to lrclk pin on pmod
        i2s_tx_sclk  : out std_logic;  --to bit clk pin on pmod
        i2s_tx_mclk  : out  std_logic -- 24.576Mhz clk
    );
end entity TOP;

architecture Behavioral of TOP is

    --------------------------------------------------------------------
    -- COMPONENT DECLARATIONS (match IP port lists)
    --------------------------------------------------------------------

    -- 1) Clock wizard (3 outputs as in the Verilog)
    component clk_wiz_0 is
        port (
            clk_out1 : out std_logic; --24.57 mzh for pmod testing
            reset    : in  std_logic;
            locked   : out std_logic;
            clk_in1  : in  std_logic --100mhz source clk
        );
    end component;

--    -- 2) FIR compiler (24-bit data, no m_axis_data_tready)
--    component fir_compiler_0 is
--        port (
--            aclk                : in  std_logic;
--            s_axis_data_tvalid  : in  std_logic;
--            s_axis_data_tready  : out std_logic;
--            s_axis_data_tdata   : in  std_logic_vector(23 downto 0);
--            s_axis_config_tvalid: in  std_logic;
--            s_axis_config_tready: out std_logic;
--            s_axis_config_tdata : in  std_logic_vector(7 downto 0);
--            m_axis_data_tvalid  : out std_logic;
--            m_axis_data_tdata   : out std_logic_vector(23 downto 0)
--        );
--    end component;

    -- 3) I2S receiver
    component i2s_receiver_inputs is
        port (
            s_axi_ctrl_aclk    : in  std_logic;
            s_axi_ctrl_aresetn : in  std_logic;
            aud_mclk           : in  std_logic;
            aud_mrst           : in  std_logic;
            m_axis_aud_aclk    : in  std_logic;
            m_axis_aud_aresetn : in  std_logic;

            s_axi_ctrl_awvalid : in  std_logic;
            s_axi_ctrl_awready : out std_logic;
            s_axi_ctrl_awaddr  : in  std_logic_vector(7 downto 0);

            s_axi_ctrl_wvalid  : in  std_logic;
            s_axi_ctrl_wready  : out std_logic;
            s_axi_ctrl_wdata   : in  std_logic_vector(31 downto 0);

            s_axi_ctrl_bvalid  : out std_logic;
            s_axi_ctrl_bready  : in  std_logic;
            s_axi_ctrl_bresp   : out std_logic_vector(1 downto 0);

            s_axi_ctrl_arvalid : in  std_logic;
            s_axi_ctrl_arready : out std_logic;
            s_axi_ctrl_araddr  : in  std_logic_vector(7 downto 0);

            s_axi_ctrl_rvalid  : out std_logic;
            s_axi_ctrl_rready  : in  std_logic;
            s_axi_ctrl_rdata   : out std_logic_vector(31 downto 0);
            s_axi_ctrl_rresp   : out std_logic_vector(1 downto 0);

            irq                : out std_logic;

            lrclk_out          : out std_logic;
            sclk_out           : out std_logic;
            sdata_0_in         : in  std_logic;
            sdata_1_in         : in  std_logic;

            m_axis_aud_tdata   : out std_logic_vector(31 downto 0);
            m_axis_aud_tid     : out std_logic_vector(2 downto 0);
            m_axis_aud_tvalid  : out std_logic;
            m_axis_aud_tready  : in  std_logic
        );
    end component;

    -- 4) I2S transmitter
    component i2s_transmitter_0 is
        port (
            s_axi_ctrl_aclk    : in  std_logic;
            s_axi_ctrl_aresetn : in  std_logic;
            aud_mclk           : in  std_logic;
            aud_mrst           : in  std_logic;
            s_axis_aud_aclk    : in  std_logic;
            s_axis_aud_aresetn : in  std_logic;

            s_axi_ctrl_awvalid : in  std_logic;
            s_axi_ctrl_awready : out std_logic;
            s_axi_ctrl_awaddr  : in  std_logic_vector(7 downto 0);

            s_axi_ctrl_wvalid  : in  std_logic;
            s_axi_ctrl_wready  : out std_logic;
            s_axi_ctrl_wdata   : in  std_logic_vector(31 downto 0);

            s_axi_ctrl_bvalid  : out std_logic;
            s_axi_ctrl_bready  : in  std_logic;
            s_axi_ctrl_bresp   : out std_logic_vector(1 downto 0);

            s_axi_ctrl_arvalid : in  std_logic;
            s_axi_ctrl_arready : out std_logic;
            s_axi_ctrl_araddr  : in  std_logic_vector(7 downto 0);

            s_axi_ctrl_rvalid  : out std_logic;
            s_axi_ctrl_rready  : in  std_logic;
            s_axi_ctrl_rdata   : out std_logic_vector(31 downto 0);
            s_axi_ctrl_rresp   : out std_logic_vector(1 downto 0);

            irq                : out std_logic;

            lrclk_out          : out std_logic;
            sclk_out           : out std_logic;
            sdata_0_out        : out std_logic;
            sdata_1_out        : out std_logic;

            s_axis_aud_tdata   : in  std_logic_vector(31 downto 0);
            s_axis_aud_tid     : in  std_logic_vector(2 downto 0);
            s_axis_aud_tvalid  : in  std_logic;
            s_axis_aud_tready  : out std_logic
        );
    end component;

    --------------------------------------------------------------------
    -- SIGNALS 
    --------------------------------------------------------------------
    signal clk_1_sys    : std_logic; --24.576 mhz clk
    signal clk_locked   : std_logic; --clk wizard
    signal rst_sys_n    : std_logic;
    signal rst_sys_not  : std_logic;

    -- AXIS stream (32-bit from/to I2S)
    signal rx_tdata     : std_logic_vector(31 downto 0);
    signal rx_tvalid    : std_logic;
    signal rx_tready    : std_logic;

    signal tx_tdata     : std_logic_vector(31 downto 0);
    signal tx_tvalid    : std_logic;
    -- tx_tready is not needed as a signal; we'll leave it open

    -- FIR side (24-bit)
    signal fir_in_tdata   : std_logic_vector(23 downto 0);
    signal fir_in_tvalid  : std_logic;
    signal fir_in_tready  : std_logic;
    signal fir_out_tdata  : std_logic_vector(23 downto 0);
    signal fir_out_tvalid : std_logic;

    -- dummy for tids
    signal rx_tid_dummy   : std_logic_vector(2 downto 0);
    signal tx_tid_const   : std_logic_vector(2 downto 0) := (others => '0');

    -- shared i2s signials for pmod
    signal i2s_lrclk : std_logic;
    signal i2s_sclk  : std_logic;
    signal i2s_sdin  : std_logic;  -- into DAC
    signal i2s_sdout : std_logic;  -- from ADC
    
begin
    -- MCLK goes to both codecs
    i2s_rx_mclk <= clk_1_sys;
    i2s_tx_mclk <= clk_1_sys;
    
    -- ONE set of LRCLK/SCLK drives both codecs
    i2s_tx_lrclk <= i2s_lrclk;
    i2s_rx_lrclk <= i2s_lrclk;
    
    i2s_tx_sclk <= i2s_sclk;
    i2s_rx_sclk <= i2s_sclk;
    
    -- Data directions
    i2s_tx_sdata <= i2s_sdin;
    i2s_sdout <= i2s_rx_sdata;

    rst_sys_n   <= resetn_in;
    rst_sys_not <= not resetn_in;

    ----------------------------------------------------------------
    -- 1) Clock wizard instance
    ----------------------------------------------------------------
    u_clk_wiz : clk_wiz_0
        port map (
            clk_out1 => clk_1_sys,       --clk_1_sys is the 24.576
            reset    => rst_sys_not,
            locked   => clk_locked,
            clk_in1  => clk_in            --clk_in is the 100mhz clk
        );

    ----------------------------------------------------------------
    -- 2) I2S receiver instance
    ----------------------------------------------------------------
    u_i2s_rx : i2s_receiver_inputs
        port map (
            s_axi_ctrl_aclk    => clk_in,
            s_axi_ctrl_aresetn => rst_sys_n,
            aud_mclk           => clk_1_sys,
            aud_mrst           => rst_sys_not,
            m_axis_aud_aclk    => clk_in,
            m_axis_aud_aresetn => rst_sys_n,

            -- AXI-Lite tied off
            s_axi_ctrl_awvalid => '0',
            s_axi_ctrl_awready => open,
            s_axi_ctrl_awaddr  => (others => '0'),

            s_axi_ctrl_wvalid  => '0',
            s_axi_ctrl_wready  => open,
            s_axi_ctrl_wdata   => (others => '0'),

            s_axi_ctrl_bvalid  => open,
            s_axi_ctrl_bready  => '0',
            s_axi_ctrl_bresp   => open,

            s_axi_ctrl_arvalid => '0',
            s_axi_ctrl_arready => open,
            s_axi_ctrl_araddr  => (others => '0'),

            s_axi_ctrl_rvalid  => open,
            s_axi_ctrl_rready  => '0',
            s_axi_ctrl_rdata   => open,
            s_axi_ctrl_rresp   => open,

            irq                => open,

            -- I2S pins
            lrclk_out          => open,
            sclk_out           => open,
            sdata_0_in         => i2s_sdout,
            sdata_1_in         => '0',

            -- AXIS audio out
            m_axis_aud_tdata   => rx_tdata, --[27:4] actuall sample bits
            m_axis_aud_tid     => rx_tid_dummy, --lines for mux select not routed right now
            m_axis_aud_tvalid  => rx_tvalid,
            m_axis_aud_tready  => rx_tready
        );

    ----------------------------------------------------------------
    -- 3) FIR compiler instance
    ----------------------------------------------------------------

    -- Simple wiring: 32 -> 24 bits into FIR (drop lowest 8 bits)
    --fir_in_tdata  <= rx_tdata(31 downto 8);
    --fir_in_tvalid <= rx_tvalid;
    --rx_tready     <= fir_in_tready;

--    u_fir : fir_compiler_0
--        port map (
--            aclk                => clk_sys,
--            s_axis_data_tvalid  => fir_in_tvalid,
--            s_axis_data_tready  => fir_in_tready,
--            s_axis_data_tdata   => fir_in_tdata,
--            s_axis_config_tvalid=> '0',
--            s_axis_config_tready=> open,
--            s_axis_config_tdata => (others => '0'),
--            m_axis_data_tvalid  => fir_out_tvalid,
--            m_axis_data_tdata   => fir_out_tdata
--        );
 
    ----------------------------------------------------------------
    -- 4) I2S transmitter instance
    ----------------------------------------------------------------

    -- 24 -> 32 bits for I2S (simple zero-extend)
    tx_tdata  <= (7 downto 0 => '0') & fir_out_tdata;
    tx_tvalid <= fir_out_tvalid;

    u_i2s_tx : i2s_transmitter_0
        port map (
            s_axi_ctrl_aclk    => clk_in,
            s_axi_ctrl_aresetn => rst_sys_n,
            aud_mclk           => clk_1_sys,
            aud_mrst           => rst_sys_not,
            s_axis_aud_aclk    => clk_in,
            s_axis_aud_aresetn => rst_sys_n,

            -- AXI-Lite tied off
            s_axi_ctrl_awvalid => '0',
            s_axi_ctrl_awready => open,
            s_axi_ctrl_awaddr  => (others => '0'),

            s_axi_ctrl_wvalid  => '0',
            s_axi_ctrl_wready  => open,
            s_axi_ctrl_wdata   => (others => '0'),

            s_axi_ctrl_bvalid  => open,
            s_axi_ctrl_bready  => '0',
            s_axi_ctrl_bresp   => open,

            s_axi_ctrl_arvalid => '0',
            s_axi_ctrl_arready => open,
            s_axi_ctrl_araddr  => (others => '0'),

            s_axi_ctrl_rvalid  => open,
            s_axi_ctrl_rready  => '0',
            s_axi_ctrl_rdata   => open,
            s_axi_ctrl_rresp   => open,

            irq                => open,

            -- I2S pins
            lrclk_out          => i2s_tx_lrclk, 
            sclk_out           => i2s_tx_sclk, -- bit clock
            sdata_0_out        => i2s_tx_sdata, -- data streams 1,2
            sdata_1_out        => open,

            -- AXIS audio in
            s_axis_aud_tdata   => rx_tdata, --input data
            s_axis_aud_tid     => tx_tid_const, -- not implemented used for mux select
            s_axis_aud_tvalid  => rx_tvalid,
            s_axis_aud_tready  => rx_tready
        );

end Behavioral;
