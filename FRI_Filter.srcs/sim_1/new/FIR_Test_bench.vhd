-- tb_top.vhd (UPDATED)
-- Works with your updated TOP (sync resets, divider=96k, etc.)
--
-- Fixes:
--  1) No to_hstring: includes a local to_hex() function
--  2) No reading OUT ports: stubs use internal *_r signals and assign to outputs
--
-- What to watch:
--  - i2s_tx_mclk, i2s_tx_sclk, i2s_tx_lrclk
--  - i2s_rx_sdata, i2s_tx_sdata
--  - adc_left/right (generated input pattern)
--  - dac_left/right (decoded DAC stream)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_top is
end entity;

architecture sim of tb_top is

  ----------------------------------------------------------------------
  -- Helper: convert std_logic_vector to hex string (no to_hstring needed)
  ----------------------------------------------------------------------
  function hex_digit(n : natural) return character is
  begin
    case n is
      when 0  => return '0';
      when 1  => return '1';
      when 2  => return '2';
      when 3  => return '3';
      when 4  => return '4';
      when 5  => return '5';
      when 6  => return '6';
      when 7  => return '7';
      when 8  => return '8';
      when 9  => return '9';
      when 10 => return 'A';
      when 11 => return 'B';
      when 12 => return 'C';
      when 13 => return 'D';
      when 14 => return 'E';
      when others => return 'F';
    end case;
  end function;

  function to_hex(slv : std_logic_vector) return string is
    constant N : natural := (slv'length + 3) / 4;  -- hex digits
    variable res : string(1 to N);
    variable u   : unsigned(slv'length-1 downto 0);
    variable nib : natural;
  begin
    u := unsigned(slv);
    for i in 0 to N-1 loop
      -- take nibble from MSB side
      nib := to_integer(u(u'left - i*4 downto u'left - i*4 - 3));
      res(i+1) := hex_digit(nib);
    end loop;
    return res;
  end function;

  -- DUT ports
  signal clk_in        : std_logic := '0';
  signal resetn_in     : std_logic := '0';

  signal i2s_rx_sdata  : std_logic := '0';
  signal i2s_rx_lrclk  : std_logic;
  signal i2s_rx_sclk   : std_logic;
  signal i2s_rx_mclk   : std_logic;

  signal i2s_tx_sdata  : std_logic;
  signal i2s_tx_lrclk  : std_logic;
  signal i2s_tx_sclk   : std_logic;
  signal i2s_tx_mclk   : std_logic;

  ----------------------------------------------------------------------
  -- Timing constants
  ----------------------------------------------------------------------
  constant T_CLK100   : time := 50 ms;   -- 100 MHz clock period
  constant SLOT_BITS  : integer := 32;   -- 32-bit slot
  
  --ADC Constants
constant ADC_LEFT_BASE  : unsigned(31 downto 0) := unsigned'(x"A0000000");
constant ADC_RIGHT_BASE : unsigned(31 downto 0) := unsigned'(x"50000000");
  ----------------------------------------------------------------------
  -- ADC model state (drives i2s_rx_sdata)
  ----------------------------------------------------------------------
  signal adc_left   : std_logic_vector(SLOT_BITS-1 downto 0) := (others => '0');
  signal adc_right  : std_logic_vector(SLOT_BITS-1 downto 0) := (others => '0');
  signal adc_shift  : std_logic_vector(SLOT_BITS-1 downto 0) := (others => '0');
  signal adc_bitcnt : integer range 0 to SLOT_BITS := 0;

  ----------------------------------------------------------------------
  -- DAC decode monitor (reconstruct from i2s_tx_sdata)
  ----------------------------------------------------------------------
  signal dac_shift  : std_logic_vector(SLOT_BITS-1 downto 0) := (others => '0');
  signal dac_bitcnt : integer range 0 to SLOT_BITS := 0;
  signal dac_left   : std_logic_vector(SLOT_BITS-1 downto 0) := (others => '0');
  signal dac_right  : std_logic_vector(SLOT_BITS-1 downto 0) := (others => '0');

begin

  ----------------------------------------------------------------------
  -- Instantiate DUT (your updated TOP must be in work library)
  ----------------------------------------------------------------------
  dut: entity work.TOP
    port map (
      clk_in       => clk_in,
      resetn_in    => resetn_in,
      i2s_rx_sdata => i2s_rx_sdata,
      i2s_rx_lrclk => i2s_rx_lrclk,
      i2s_rx_sclk  => i2s_rx_sclk,
      i2s_rx_mclk  => i2s_rx_mclk,
      i2s_tx_sdata => i2s_tx_sdata,
      i2s_tx_lrclk => i2s_tx_lrclk,
      i2s_tx_sclk  => i2s_tx_sclk,
      i2s_tx_mclk  => i2s_tx_mclk
    );

  ----------------------------------------------------------------------
  -- 100 MHz clock generator
  ----------------------------------------------------------------------
  clk_in <= not clk_in after T_CLK100/2;

  ----------------------------------------------------------------------
  -- Reset sequence
  ----------------------------------------------------------------------
  process
  begin
    resetn_in <= '0';
    wait for 300 ns;
    resetn_in <= '1';
    wait;
  end process;

  ----------------------------------------------------------------------
  -- ADC Model: drives SDOUT (i2s_rx_sdata)
  --
  -- Assumptions (I2S typical):
  --   - Data changes on falling edge of SCLK
  --   - Data sampled on rising edge
  --   - "1-bit delay": first bit after LRCLK boundary is dummy
  --
  -- We align the ADC model to the TX-generated clocks from DUT:
  --   i2s_tx_lrclk, i2s_tx_sclk
  ----------------------------------------------------------------------
  process(i2s_tx_sclk)
    variable sample_id : unsigned(15 downto 0) := (others => '0');
  begin
    if falling_edge(i2s_tx_sclk) then

      -- Start-of-slot: reload shift reg
      if adc_bitcnt = 0 then
        -- Visible patterns so you can spot bit shifts easily:
        -- left  = 0xA0000000 + sample_id
        -- right = 0x50000000 + sample_id
        -- typed base patterns (avoid ambiguous x"..." conversions)
        
        -- inside the process where you build samples:
        adc_left  <= std_logic_vector(ADC_LEFT_BASE  + resize(sample_id, 32));
        adc_right <= std_logic_vector(ADC_RIGHT_BASE + resize(sample_id, 32));
        
        
        if i2s_tx_lrclk = '0' then
          adc_shift <= adc_left;
        else
          adc_shift <= adc_right;
          sample_id := sample_id + 1; -- bump once per stereo frame
        end if;

        adc_bitcnt <= SLOT_BITS;
      end if;

      -- I2S 1-bit delay: output dummy bit first after reload
      if adc_bitcnt = SLOT_BITS then
        i2s_rx_sdata <= '0';
      else
        i2s_rx_sdata <= adc_shift(SLOT_BITS-1); -- MSB first
        adc_shift    <= adc_shift(SLOT_BITS-2 downto 0) & '0';
      end if;

      if adc_bitcnt > 0 then
        adc_bitcnt <= adc_bitcnt - 1;
      end if;

    end if;
  end process;

  ----------------------------------------------------------------------
  -- DAC Decode Monitor: reconstruct from SDIN (i2s_tx_sdata)
  --
  -- We sample on rising edge, and we ignore the first bit after slot start
  -- to match I2S 1-bit delay.
  ----------------------------------------------------------------------
  process(i2s_tx_sclk)
  begin
    if rising_edge(i2s_tx_sclk) then

      if dac_bitcnt = 0 then
        dac_bitcnt <= SLOT_BITS;
      end if;

      -- Ignore first bit after slot start (I2S delay)
      if dac_bitcnt = SLOT_BITS then
        null;
      else
        dac_shift <= dac_shift(SLOT_BITS-2 downto 0) & i2s_tx_sdata;
      end if;

      if dac_bitcnt > 0 then
        dac_bitcnt <= dac_bitcnt - 1;
      end if;

      -- When finishing a slot, latch based on LRCLK
      if dac_bitcnt = 1 then
        if i2s_tx_lrclk = '0' then
          dac_left <= dac_shift;
        else
          dac_right <= dac_shift;
        end if;
      end if;

    end if;
  end process;

  ----------------------------------------------------------------------
  -- Print once per right-channel boundary (LRCLK rising edge in our convention)
  ----------------------------------------------------------------------
  process(i2s_tx_lrclk)
  begin
    if rising_edge(i2s_tx_lrclk) then
      report "DAC left=0x" & to_hex(dac_left) &
             " right=0x"  & to_hex(dac_right);
    end if;
  end process;

end architecture;


--------------------------------------------------------------------------------
-- ======================== BEHAVIORAL STUBS ==================================
-- These let the sim run without Xilinx IP libraries.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- clk_wiz_0 stub
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity clk_wiz_0 is
  port (
    clk_out1 : out std_logic;
    reset    : in  std_logic; -- active-high
    locked   : out std_logic;
    clk_in1  : in  std_logic
  );
end entity;

architecture beh of clk_wiz_0 is
  constant T_MCLK : time := 40.690104 ns; -- ~24.576 MHz
begin
  process
  begin
    clk_out1 <= '0';
    locked   <= '0';
    wait until reset = '0';
    wait for 200 ns;
    locked <= '1';

    while reset = '0' loop
      clk_out1 <= '1'; wait for T_MCLK/2;
      clk_out1 <= '0'; wait for T_MCLK/2;
    end loop;

    locked <= '0';
  end process;
end architecture;


--------------------------------------------------------------------------------
-- i2s_transmitter_0 stub (FIXED OUT-READ ISSUES)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_transmitter_0 is
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
end entity;

architecture beh of i2s_transmitter_0 is
  signal div_reg  : unsigned(7 downto 0) := to_unsigned(2,8); -- default for your 96k setup
  signal en_reg   : std_logic := '0';

  signal sclk_i   : std_logic := '0';
  signal lrclk_i  : std_logic := '0';
  signal mclk_cnt : unsigned(7 downto 0) := (others => '0');

  -- internal bvalid so we can read it
  signal bvalid_r : std_logic := '0';

  signal bitcnt    : integer range 0 to 31 := 0;
  signal shifter   : std_logic_vector(31 downto 0) := (others => '0');
  signal have_word : std_logic := '0';
begin
  -- Tie-offs
  s_axi_ctrl_arready <= '1';
  s_axi_ctrl_rvalid  <= '0';
  s_axi_ctrl_rdata   <= (others => '0');
  s_axi_ctrl_rresp   <= "00";
  irq                <= '0';
  sdata_1_out        <= '0';

  -- drive output bvalid from internal reg
  s_axi_ctrl_bvalid <= bvalid_r;
  s_axi_ctrl_bresp  <= "00";

  -- AXI-lite write (simplified)
  process(s_axi_ctrl_aclk)
  begin
    if rising_edge(s_axi_ctrl_aclk) then
      if s_axi_ctrl_aresetn = '0' then
        s_axi_ctrl_awready <= '0';
        s_axi_ctrl_wready  <= '0';
        bvalid_r           <= '0';
        div_reg            <= to_unsigned(2,8);
        en_reg             <= '0';
      else
        s_axi_ctrl_awready <= '1';
        s_axi_ctrl_wready  <= '1';

        if (s_axi_ctrl_awvalid = '1' and s_axi_ctrl_wvalid = '1') then
          if s_axi_ctrl_awaddr = x"20" then
            div_reg <= unsigned(s_axi_ctrl_wdata(7 downto 0));
          elsif s_axi_ctrl_awaddr = x"08" then
            en_reg <= s_axi_ctrl_wdata(0);
          end if;
          bvalid_r <= '1';
        end if;

        if (bvalid_r = '1' and s_axi_ctrl_bready = '1') then
          bvalid_r <= '0';
        end if;
      end if;
    end if;
  end process;

  -- SCLK generation: toggle every div_reg MCLK cycles => MCLK/SCLK = 2*div_reg
  process(aud_mclk)
  begin
    if rising_edge(aud_mclk) then
      if aud_mrst = '1' then
        mclk_cnt <= (others => '0');
        sclk_i   <= '0';
      elsif en_reg = '1' then
        if mclk_cnt = div_reg-1 then
          mclk_cnt <= (others => '0');
          sclk_i   <= not sclk_i;
        else
          mclk_cnt <= mclk_cnt + 1;
        end if;
      end if;
    end if;
  end process;
  sclk_out <= sclk_i;

  -- LRCLK generation: toggle every 32 SCLK rising edges (32-bit slots)
  process(sclk_i)
    variable half_cnt : integer range 0 to 31 := 0;
  begin
    if rising_edge(sclk_i) then
      if aud_mrst = '1' then
        lrclk_i  <= '0';
        half_cnt := 0;
      elsif en_reg = '1' then
        if half_cnt = 31 then
          half_cnt := 0;
          lrclk_i  <= not lrclk_i;
        else
          half_cnt := half_cnt + 1;
        end if;
      end if;
    end if;
  end process;
  lrclk_out <= lrclk_i;

  -- AXIS ready when enabled
  s_axis_aud_tready <= en_reg;

  -- Serialize with 1-bit I2S delay; change data on falling edge
  process(sclk_i)
  begin
    if falling_edge(sclk_i) then
      if aud_mrst = '1' then
        bitcnt      <= 0;
        sdata_0_out <= '0';
        have_word   <= '0';
        shifter     <= (others => '0');
      elsif en_reg = '1' then
        if bitcnt = 0 then
          if s_axis_aud_tvalid = '1' then
            shifter   <= s_axis_aud_tdata;
            have_word <= '1';
          else
            have_word <= '0';
          end if;

          bitcnt      <= 31;
          sdata_0_out <= '0'; -- dummy bit (I2S delay)
        else
          if have_word = '1' then
            sdata_0_out <= shifter(31);
            shifter     <= shifter(30 downto 0) & '0';
          else
            sdata_0_out <= '0';
          end if;
          bitcnt <= bitcnt - 1;
        end if;
      end if;
    end if;
  end process;

end architecture;


--------------------------------------------------------------------------------
-- i2s_receiver_inputs stub (FIXED OUT-READ ISSUES)
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2s_receiver_inputs is
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
end entity;

architecture beh of i2s_receiver_inputs is
  signal div_reg  : unsigned(7 downto 0) := to_unsigned(2,8);
  signal en_reg   : std_logic := '0';

  signal sclk_i   : std_logic := '0';
  signal lrclk_i  : std_logic := '0';
  signal mclk_cnt : unsigned(7 downto 0) := (others => '0');

  -- internal bvalid / tvalid so we can read them
  signal bvalid_r : std_logic := '0';
  signal tvalid_r : std_logic := '0';

  signal bitcnt   : integer range 0 to 31 := 0;
  signal shifter  : std_logic_vector(31 downto 0) := (others => '0');
  signal skip1    : std_logic := '1';
begin
  -- Tie-offs
  s_axi_ctrl_arready <= '1';
  s_axi_ctrl_rvalid  <= '0';
  s_axi_ctrl_rdata   <= (others => '0');
  s_axi_ctrl_rresp   <= "00";
  irq                <= '0';
  m_axis_aud_tid     <= (others => '0');

  -- outputs driven from internal regs
  s_axi_ctrl_bvalid  <= bvalid_r;
  s_axi_ctrl_bresp   <= "00";
  m_axis_aud_tvalid  <= tvalid_r;

  -- AXI-lite write
  process(s_axi_ctrl_aclk)
  begin
    if rising_edge(s_axi_ctrl_aclk) then
      if s_axi_ctrl_aresetn = '0' then
        s_axi_ctrl_awready <= '0';
        s_axi_ctrl_wready  <= '0';
        bvalid_r           <= '0';
        div_reg            <= to_unsigned(2,8);
        en_reg             <= '0';
      else
        s_axi_ctrl_awready <= '1';
        s_axi_ctrl_wready  <= '1';

        if (s_axi_ctrl_awvalid = '1' and s_axi_ctrl_wvalid = '1') then
          if s_axi_ctrl_awaddr = x"20" then
            div_reg <= unsigned(s_axi_ctrl_wdata(7 downto 0));
          elsif s_axi_ctrl_awaddr = x"08" then
            en_reg <= s_axi_ctrl_wdata(0);
          end if;
          bvalid_r <= '1';
        end if;

        if (bvalid_r = '1' and s_axi_ctrl_bready = '1') then
          bvalid_r <= '0';
        end if;
      end if;
    end if;
  end process;

  -- SCLK gen
  process(aud_mclk)
  begin
    if rising_edge(aud_mclk) then
      if aud_mrst = '1' then
        mclk_cnt <= (others => '0');
        sclk_i   <= '0';
      elsif en_reg = '1' then
        if mclk_cnt = div_reg-1 then
          mclk_cnt <= (others => '0');
          sclk_i   <= not sclk_i;
        else
          mclk_cnt <= mclk_cnt + 1;
        end if;
      end if;
    end if;
  end process;
  sclk_out <= sclk_i;

  -- LRCLK gen (32-bit slots)
  process(sclk_i)
    variable half_cnt : integer range 0 to 31 := 0;
  begin
    if rising_edge(sclk_i) then
      if aud_mrst = '1' then
        lrclk_i  <= '0';
        half_cnt := 0;
      elsif en_reg = '1' then
        if half_cnt = 31 then
          half_cnt := 0;
          lrclk_i  <= not lrclk_i;
        else
          half_cnt := half_cnt + 1;
        end if;
      end if;
    end if;
  end process;
  lrclk_out <= lrclk_i;

  -- Deserialize on rising edge; skip first bit after boundary (I2S delay)
  process(sclk_i)
  begin
    if rising_edge(sclk_i) then
      if aud_mrst = '1' then
        bitcnt    <= 0;
        shifter   <= (others => '0');
        tvalid_r  <= '0';
        skip1     <= '1';
      elsif en_reg = '1' then
        if bitcnt = 0 then
          bitcnt   <= 31;
          skip1    <= '1';
          tvalid_r <= '0';
        else
          if skip1 = '1' then
            skip1 <= '0'; -- ignore first bit
          else
            shifter <= shifter(30 downto 0) & sdata_0_in;
          end if;
          bitcnt <= bitcnt - 1;
        end if;

        -- present word at end of slot
        if bitcnt = 1 then
          m_axis_aud_tdata <= shifter;
          tvalid_r         <= '1';
        elsif (tvalid_r = '1' and m_axis_aud_tready = '1') then
          tvalid_r <= '0';
        end if;

      end if;
    end if;
  end process;

end architecture;
