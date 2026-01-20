library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity TOP is
    port (
        clk_in      : in  std_logic; -- 100 MHz
        resetn_in   : in  std_logic; -- active-low reset button

        -- ADC SDOUT from Pmod (pin 10)
        i2s_rx_sdata : in  std_logic;

        -- ADC clocks to Pmod (pins 7/8/9)
        i2s_rx_lrclk : out std_logic;
        i2s_rx_sclk  : out std_logic;
        i2s_rx_mclk  : out std_logic;

        -- DAC signals to Pmod (pins 1/2/3/4)
        i2s_tx_sdata : out std_logic;
        i2s_tx_lrclk : out std_logic;
        i2s_tx_sclk  : out std_logic;
        i2s_tx_mclk  : out std_logic
    );
end entity;

architecture Behavioral of TOP is

    --------------------------------------------------------------------
    -- COMPONENTS
    --------------------------------------------------------------------
    component clk_wiz_0 is
        port (
            clk_out1 : out std_logic; -- 24.576 MHz
            reset    : in  std_logic; -- active-high reset
            locked   : out std_logic;
            clk_in1  : in  std_logic
        );
    end component;

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
    -- CLOCKS
    --------------------------------------------------------------------
    signal clk_mclk    : std_logic;
    signal clk_locked  : std_logic;

    -- Clock wizard reset (active-high)
    signal not_reset   : std_logic;

    --------------------------------------------------------------------
    -- RESET (clean + synchronized)
    --------------------------------------------------------------------
    signal rst_async      : std_logic;  -- active-high async reset source (btn OR !locked)

    -- clk_in domain
    signal rst_sync0_sys  : std_logic := '1';
    signal rst_sync1_sys  : std_logic := '1';
    signal rst_sys        : std_logic;  -- active-high sync reset
    signal rstn_sys       : std_logic;  -- active-low reset for AXI aresetn

    -- clk_mclk domain
    signal rst_sync0_mclk : std_logic := '1';
    signal rst_sync1_mclk : std_logic := '1';
    signal rst_mclk       : std_logic;  -- active-high sync reset (audio reset)
    signal rstn_mclk      : std_logic;  -- active-low version if needed later

    --------------------------------------------------------------------
    -- I2S bus clocks to Pmod (driven by TX core)
    --------------------------------------------------------------------
    signal bus_lrclk    : std_logic;
    signal bus_sclk     : std_logic;

    --------------------------------------------------------------------
    -- AXIS loopback
    --------------------------------------------------------------------
    signal rx_tdata     : std_logic_vector(31 downto 0);
    signal rx_tvalid    : std_logic;
    signal rx_tready    : std_logic;
    signal rx_tid_dummy : std_logic_vector(2 downto 0);

    signal tx_tid_const : std_logic_vector(2 downto 0) := (others => '0');

    --------------------------------------------------------------------
    -- AXI-Lite init (TX)
    --------------------------------------------------------------------
    signal tx_awvalid, tx_wvalid : std_logic;
    signal tx_awready, tx_wready : std_logic;
    signal tx_bvalid             : std_logic;
    signal tx_bready             : std_logic := '1';
    signal tx_awaddr             : std_logic_vector(7 downto 0);
    signal tx_wdata              : std_logic_vector(31 downto 0);
    signal tx_bresp              : std_logic_vector(1 downto 0);

    -- Reads unused
    signal tx_arvalid, tx_rready : std_logic := '0';
    signal tx_arready, tx_rvalid : std_logic;
    signal tx_araddr             : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_rdata              : std_logic_vector(31 downto 0);
    signal tx_rresp              : std_logic_vector(1 downto 0);

    --------------------------------------------------------------------
    -- AXI-Lite init (RX)
    --------------------------------------------------------------------
    signal rx_awvalid_i, rx_wvalid_i : std_logic;
    signal rx_awready_i, rx_wready_i : std_logic;
    signal rx_bvalid_i               : std_logic;
    signal rx_bready_i               : std_logic := '1';
    signal rx_awaddr_i               : std_logic_vector(7 downto 0);
    signal rx_wdata_i                : std_logic_vector(31 downto 0);
    signal rx_bresp_i                : std_logic_vector(1 downto 0);

    signal rx_arvalid_i, rx_rready_i : std_logic := '0';
    signal rx_arready_i, rx_rvalid_i : std_logic;
    signal rx_araddr_i               : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_rdata_i                : std_logic_vector(31 downto 0);
    signal rx_rresp_i                : std_logic_vector(1 downto 0);

    --------------------------------------------------------------------
    -- Registers / constants
    --------------------------------------------------------------------
    -- For Fs = 96 kHz when MCLK = 24.576 MHz and 64*Fs bitclock:
    --   SCLK = 64*Fs = 6.144 MHz
    --   MCLK/SCLK = 4
    --   divider = 2 (since MCLK/SCLK = divider*2)
    constant DIVIDER_96KHZ : std_logic_vector(7 downto 0) := x"02";

    constant REG_CTRL    : std_logic_vector(7 downto 0) := x"08";
    constant REG_TIMING  : std_logic_vector(7 downto 0) := x"20";
    constant W_ENABLE    : std_logic_vector(31 downto 0) := x"00000001";

    type axi_init_state_t is (S_IDLE, S_WR_TIMING, S_WAIT_B1, S_WR_CTRL, S_WAIT_B2, S_DONE);
    signal st_tx, st_rx : axi_init_state_t := S_IDLE;

begin
    --------------------------------------------------------------------
    -- Clock wizard reset + async reset source
    --------------------------------------------------------------------
    not_reset <= not resetn_in;

    -- one simple async reset source used only for synchronizers
    rst_async <= (not resetn_in) or (not clk_locked);

    --------------------------------------------------------------------
    -- Clock wizard makes MCLK
    --------------------------------------------------------------------
    u_clk_wiz : clk_wiz_0
        port map (
            clk_out1 => clk_mclk,
            reset    => not_reset,     -- active-high reset
            locked   => clk_locked,
            clk_in1  => clk_in
        );

    --------------------------------------------------------------------
    -- Synchronize reset into clk_in domain (100 MHz)
    --------------------------------------------------------------------
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            rst_sync0_sys <= rst_async;
            rst_sync1_sys <= rst_sync0_sys;
        end if;
    end process;

    rst_sys  <= rst_sync1_sys;  -- active-high
    rstn_sys <= not rst_sys;     -- active-low for AXI resets

    --------------------------------------------------------------------
    -- Synchronize reset into clk_mclk domain (24.576 MHz)
    --------------------------------------------------------------------
    process(clk_mclk)
    begin
        if rising_edge(clk_mclk) then
            rst_sync0_mclk <= rst_async;
            rst_sync1_mclk <= rst_sync0_mclk;
        end if;
    end process;

    rst_mclk  <= rst_sync1_mclk; -- active-high, use for aud_mrst
    rstn_mclk <= not rst_mclk;

    --------------------------------------------------------------------
    -- Drive MCLK to both Pmod clock pins
    --------------------------------------------------------------------
    i2s_tx_mclk <= clk_mclk;  -- Pmod pin1 (DAC MCLK)
    i2s_rx_mclk <= clk_mclk;  -- Pmod pin7 (ADC MCLK)

    --------------------------------------------------------------------
    -- Drive *one* set of bus clocks to BOTH DAC and ADC pins
    --------------------------------------------------------------------
    i2s_tx_lrclk <= bus_lrclk; -- Pmod pin2
    i2s_tx_sclk  <= bus_sclk;  -- Pmod pin3
    i2s_rx_lrclk <= bus_lrclk; -- Pmod pin8
    i2s_rx_sclk  <= bus_sclk;  -- Pmod pin9

    --------------------------------------------------------------------
    -- AXI-Lite init FSM for TX core
    -- Writes:
    --  0x20[7:0] = divider
    --  0x08[0]   = enable
    --------------------------------------------------------------------
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            if rst_sys = '1' then
                st_tx      <= S_IDLE;
                tx_awvalid <= '0';
                tx_wvalid  <= '0';
                tx_awaddr  <= (others => '0');
                tx_wdata   <= (others => '0');
            else
                case st_tx is
                    when S_IDLE =>
                        st_tx <= S_WR_TIMING;

                    when S_WR_TIMING =>
                        tx_awaddr  <= REG_TIMING;
                        tx_wdata   <= x"000000" & DIVIDER_96KHZ;
                        tx_awvalid <= '1';
                        tx_wvalid  <= '1';
                        if (tx_awready = '1') and (tx_wready = '1') then
                            tx_awvalid <= '0';
                            tx_wvalid  <= '0';
                            st_tx <= S_WAIT_B1;
                        end if;

                    when S_WAIT_B1 =>
                        if tx_bvalid = '1' then
                            st_tx <= S_WR_CTRL;
                        end if;

                    when S_WR_CTRL =>
                        tx_awaddr  <= REG_CTRL;
                        tx_wdata   <= W_ENABLE;
                        tx_awvalid <= '1';
                        tx_wvalid  <= '1';
                        if (tx_awready = '1') and (tx_wready = '1') then
                            tx_awvalid <= '0';
                            tx_wvalid  <= '0';
                            st_tx <= S_WAIT_B2;
                        end if;

                    when S_WAIT_B2 =>
                        if tx_bvalid = '1' then
                            st_tx <= S_DONE;
                        end if;

                    when others =>
                        st_tx <= S_DONE;
                end case;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- AXI-Lite init FSM for RX core (same writes)
    --------------------------------------------------------------------
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            if rst_sys = '1' then
                st_rx       <= S_IDLE;
                rx_awvalid_i <= '0';
                rx_wvalid_i  <= '0';
                rx_awaddr_i  <= (others => '0');
                rx_wdata_i   <= (others => '0');
            else
                case st_rx is
                    when S_IDLE =>
                        st_rx <= S_WR_TIMING;

                    when S_WR_TIMING =>
                        rx_awaddr_i  <= REG_TIMING;
                        rx_wdata_i   <= x"000000" & DIVIDER_96KHZ;
                        rx_awvalid_i <= '1';
                        rx_wvalid_i  <= '1';
                        if (rx_awready_i = '1') and (rx_wready_i = '1') then
                            rx_awvalid_i <= '0';
                            rx_wvalid_i  <= '0';
                            st_rx <= S_WAIT_B1;
                        end if;

                    when S_WAIT_B1 =>
                        if rx_bvalid_i = '1' then
                            st_rx <= S_WR_CTRL;
                        end if;

                    when S_WR_CTRL =>
                        rx_awaddr_i  <= REG_CTRL;
                        rx_wdata_i   <= W_ENABLE;
                        rx_awvalid_i <= '1';
                        rx_wvalid_i  <= '1';
                        if (rx_awready_i = '1') and (rx_wready_i = '1') then
                            rx_awvalid_i <= '0';
                            rx_wvalid_i  <= '0';
                            st_rx <= S_WAIT_B2;
                        end if;

                    when S_WAIT_B2 =>
                        if rx_bvalid_i = '1' then
                            st_rx <= S_DONE;
                        end if;

                    when others =>
                        st_rx <= S_DONE;
                end case;
            end if;
        end if;
    end process;

    --------------------------------------------------------------------
    -- RX core instance
    --------------------------------------------------------------------
    u_i2s_rx : i2s_receiver_inputs
        port map (
            s_axi_ctrl_aclk    => clk_in,
            s_axi_ctrl_aresetn => rstn_sys,
            aud_mclk           => clk_mclk,
            aud_mrst           => rst_mclk,
            m_axis_aud_aclk    => clk_in,
            m_axis_aud_aresetn => rstn_sys,

            s_axi_ctrl_awvalid => rx_awvalid_i,
            s_axi_ctrl_awready => rx_awready_i,
            s_axi_ctrl_awaddr  => rx_awaddr_i,

            s_axi_ctrl_wvalid  => rx_wvalid_i,
            s_axi_ctrl_wready  => rx_wready_i,
            s_axi_ctrl_wdata   => rx_wdata_i,

            s_axi_ctrl_bvalid  => rx_bvalid_i,
            s_axi_ctrl_bready  => rx_bready_i,
            s_axi_ctrl_bresp   => rx_bresp_i,

            s_axi_ctrl_arvalid => rx_arvalid_i,
            s_axi_ctrl_arready => rx_arready_i,
            s_axi_ctrl_araddr  => rx_araddr_i,

            s_axi_ctrl_rvalid  => rx_rvalid_i,
            s_axi_ctrl_rready  => rx_rready_i,
            s_axi_ctrl_rdata   => rx_rdata_i,
            s_axi_ctrl_rresp   => rx_rresp_i,

            irq                => open,

            lrclk_out          => open,
            sclk_out           => open,
            sdata_0_in         => i2s_rx_sdata, -- ADC SDOUT from Pmod pin10
            sdata_1_in         => '0',

            m_axis_aud_tdata   => rx_tdata,
            m_axis_aud_tid     => rx_tid_dummy,
            m_axis_aud_tvalid  => rx_tvalid,
            m_axis_aud_tready  => rx_tready
        );

    --------------------------------------------------------------------
    -- TX core instance (drives the *bus* clocks and DAC SDIN)
    -- Loopback: rx_tdata/rx_tvalid go straight into TX
    --------------------------------------------------------------------
    u_i2s_tx : i2s_transmitter_0
        port map (
            s_axi_ctrl_aclk    => clk_in,
            s_axi_ctrl_aresetn => rstn_sys,
            aud_mclk           => clk_mclk,
            aud_mrst           => rst_mclk,
            s_axis_aud_aclk    => clk_in,
            s_axis_aud_aresetn => rstn_sys,

            s_axi_ctrl_awvalid => tx_awvalid,
            s_axi_ctrl_awready => tx_awready,
            s_axi_ctrl_awaddr  => tx_awaddr,

            s_axi_ctrl_wvalid  => tx_wvalid,
            s_axi_ctrl_wready  => tx_wready,
            s_axi_ctrl_wdata   => tx_wdata,

            s_axi_ctrl_bvalid  => tx_bvalid,
            s_axi_ctrl_bready  => tx_bready,
            s_axi_ctrl_bresp   => tx_bresp,

            s_axi_ctrl_arvalid => tx_arvalid,
            s_axi_ctrl_arready => tx_arready,
            s_axi_ctrl_araddr  => tx_araddr,

            s_axi_ctrl_rvalid  => tx_rvalid,
            s_axi_ctrl_rready  => tx_rready,
            s_axi_ctrl_rdata   => tx_rdata,
            s_axi_ctrl_rresp   => tx_rresp,

            irq                => open,

            lrclk_out          => bus_lrclk,
            sclk_out           => bus_sclk,
            sdata_0_out        => i2s_tx_sdata, -- DAC SDIN to Pmod pin4
            sdata_1_out        => open,

            s_axis_aud_tdata   => rx_tdata,
            s_axis_aud_tid     => tx_tid_const,
            s_axis_aud_tvalid  => rx_tvalid,
            s_axis_aud_tready  => rx_tready
        );

end Behavioral;
