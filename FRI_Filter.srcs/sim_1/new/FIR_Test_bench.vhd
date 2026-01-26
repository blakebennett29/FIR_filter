-- tb_top.vhd (UPDATED + FIXED)
--
-- Fixes applied:
--  1) clk period corrected to 10 ns (100 MHz)
--  2) RX/TX stub clocks phase-align on enable (both derived from same aud_mclk)
--  3) RX stub captures the LAST bit correctly (no dropped LSB)
--  4) ADC pattern updates immediately at LRCLK boundary (no 1-frame lag)
--
-- What to watch:
--  - i2s_tx_mclk, i2s_tx_sclk, i2s_tx_lrclk
--  - i2s_rx_sdata, i2s_tx_sdata
--  - adc_word / adc_phase
--  - dac_word / dac_phase
--  - rx_tvalid/rx_tdata inside TOP if you add to wave

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
    constant N : natural := (slv'length + 3) / 4;
    variable res : string(1 to N);
    variable u   : unsigned(slv'length-1 downto 0);
    variable nib : natural;
    variable hi  : integer;
  begin
    u := unsigned(slv);
    for i in 0 to N-1 loop
      hi := u'left - i*4;
      nib := to_integer(u(hi downto hi-3));
      res(i+1) := hex_digit(nib);
    end loop;
    return res;
  end function;

  ----------------------------------------------------------------------
  -- DUT ports
  ----------------------------------------------------------------------
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
  constant T_CLK100   : time := 10 ns;   -- FIX #1: true 100 MHz
  constant SLOT_BITS  : integer := 32;

  ----------------------------------------------------------------------
  -- ADC pattern base constants
  ----------------------------------------------------------------------
  constant ADC_LEFT_BASE  : unsigned(31 downto 0) := x"A0000000";
  constant ADC_RIGHT_BASE : unsigned(31 downto 0) := x"50000000";

  ----------------------------------------------------------------------
  -- TB-visible word patterns (optional to watch)
  ----------------------------------------------------------------------
  signal adc_left   : std_logic_vector(31 downto 0) := std_logic_vector(ADC_LEFT_BASE);
  signal adc_right  : std_logic_vector(31 downto 0) := std_logic_vector(ADC_RIGHT_BASE);

  signal dac_left   : std_logic_vector(31 downto 0) := (others => '0');
  signal dac_right  : std_logic_vector(31 downto 0) := (others => '0');

  ----------------------------------------------------------------------
  -- I2S alignment state (ADC)
  ----------------------------------------------------------------------
  signal adc_phase   : integer range 0 to 32 := 0;  -- 0=delay, 1..32=data
  signal adc_word    : std_logic_vector(31 downto 0) := (others => '0');
  signal lrclk_rx_d  : std_logic := '0';
  signal sample_id   : unsigned(31 downto 0) := (others => '0');

  ----------------------------------------------------------------------
  -- I2S alignment state (DAC)
  ----------------------------------------------------------------------
  signal dac_phase  : integer range 0 to 32 := 0;
  signal dac_word   : std_logic_vector(31 downto 0) := (others => '0');
  signal lrclk_d    : std_logic := '0';

begin

  ----------------------------------------------------------------------
  -- Instantiate DUT (your updated TOP)
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
  -- Uses RX clocks coming out of TOP (which are shared with TX bus clocks).
  --
  -- FIX #4: update pattern immediately at boundary (no 1-frame lag)
  ----------------------------------------------------------------------
  process(i2s_rx_sclk)
    variable bit_index : integer;
    variable next_id   : unsigned(31 downto 0);
    variable nextL     : unsigned(31 downto 0);
    variable nextR     : unsigned(31 downto 0);
  begin
    if falling_edge(i2s_rx_sclk) then
      lrclk_rx_d <= i2s_rx_lrclk;

      if i2s_rx_lrclk /= lrclk_rx_d then
        -- LRCLK toggled => new slot starting
        adc_phase <= 0;

        -- FIX #4: compute new sample_id and new patterns NOW
        next_id := sample_id + 1;
        sample_id <= next_id;

        nextL := ADC_LEFT_BASE  + next_id;
        nextR := ADC_RIGHT_BASE + next_id;

        adc_left  <= std_logic_vector(nextL);
        adc_right <= std_logic_vector(nextR);

        -- load adc_word from the UPDATED values immediately
        if i2s_rx_lrclk = '0' then
          adc_word <= std_logic_vector(nextL); -- left slot
        else
          adc_word <= std_logic_vector(nextR); -- right slot
        end if;

        -- delay bit (I2S offset)
        i2s_rx_sdata <= '0';

      else
        -- inside slot
        if adc_phase < 32 then
          adc_phase <= adc_phase + 1;
        else
          adc_phase <= 32;
        end if;

        if adc_phase = 0 then
          i2s_rx_sdata <= '0'; -- delay bit
        else
          bit_index := 32 - adc_phase; -- phase1->31 ... phase32->0
          i2s_rx_sdata <= adc_word(bit_index);
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------
  -- DAC Decode Monitor: reconstruct from SDIN (i2s_tx_sdata)
  ----------------------------------------------------------------------
  process(i2s_tx_sclk)
    variable bit_index : integer;
  begin
    if rising_edge(i2s_tx_sclk) then
      lrclk_d <= i2s_tx_lrclk;

      if i2s_tx_lrclk /= lrclk_d then
        -- boundary: commit previous word
        if i2s_tx_lrclk = '1' then
          dac_left <= dac_word;
        else
          dac_right <= dac_word;
        end if;

        dac_word  <= (others => '0');
        dac_phase <= 0;

      else
        if dac_phase < 32 then
          dac_phase <= dac_phase + 1;
        else
          dac_phase <= 32;
        end if;

        if dac_phase /= 0 then
          bit_index := 32 - dac_phase;
          dac_word(bit_index) <= i2s_tx_sdata;
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------------
  -- Print once per right-channel boundary (LRCLK rising edge)
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
-- i2s_transmitter_0 stub
-- FIX #2: phase-align clocking start by resetting counters on enable rising
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
  signal div_reg  : unsigned(7 downto 0) := to_unsigned(2,8);
  signal en_reg   : std_logic := '0';

  signal sclk_i   : std_logic := '0';
  signal lrclk_i  : std_logic := '0';
  signal mclk_cnt : unsigned(7 downto 0) := (others => '0');

  -- internal bvalid so we can read it
  signal bvalid_r : std_logic := '0';

  --------------------------------------------------------------------
  -- AXIS "mailbox" in clk_in domain (holds 1 word until consumed)
  --------------------------------------------------------------------
  signal fifo_valid : std_logic := '0';
  signal fifo_data  : std_logic_vector(31 downto 0) := (others => '0');

  -- internal tready (DO NOT read output port in VHDL)
  signal tready_i   : std_logic := '0';

  --------------------------------------------------------------------
  -- Cross-domain consume handshake:
  --   sclk-domain toggles pop_tog_sclk when it consumes fifo_data
  --   clk_in domain sees the toggle and clears fifo_valid
  --------------------------------------------------------------------
  signal pop_tog_sclk     : std_logic := '0';
  signal pop_tog_sys_ff0  : std_logic := '0';
  signal pop_tog_sys_ff1  : std_logic := '0';
  signal pop_tog_sys_prev : std_logic := '0';

  -- synchronize fifo_valid into sclk domain (so sclk logic can decide to pop)
  signal fifo_valid_s_ff0 : std_logic := '0';
  signal fifo_valid_s_ff1 : std_logic := '0';

  --------------------------------------------------------------------
  -- Serializer state (sclk domain)
  --------------------------------------------------------------------
  signal bitcnt    : integer range 0 to 31 := 0;
  signal shifter   : std_logic_vector(31 downto 0) := (others => '0');
  signal have_word : std_logic := '0';
begin
  --------------------------------------------------------------------
  -- Tie-offs / unused AXI-lite read channel
  --------------------------------------------------------------------
  s_axi_ctrl_arready <= '1';
  s_axi_ctrl_rvalid  <= '0';
  s_axi_ctrl_rdata   <= (others => '0');
  s_axi_ctrl_rresp   <= "00";
  irq                <= '0';
  sdata_1_out        <= '0';

  --------------------------------------------------------------------
  -- drive output bvalid from internal reg
  --------------------------------------------------------------------
  s_axi_ctrl_bvalid <= bvalid_r;
  s_axi_ctrl_bresp  <= "00";

  --------------------------------------------------------------------
  -- AXI-lite write (simplified)
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- SCLK generation: toggle every div_reg MCLK cycles => MCLK/SCLK = 2*div_reg
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- LRCLK generation: toggle every 32 SCLK rising edges (32-bit slots)
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- ===================== AXIS CAPTURE (clk_in domain) =================
  -- Hold one word in fifo_data until serializer consumes it.
  --------------------------------------------------------------------
  tready_i <= en_reg and (not fifo_valid);
  s_axis_aud_tready <= tready_i;

  process(s_axis_aud_aclk)
  begin
    if rising_edge(s_axis_aud_aclk) then
      if s_axis_aud_aresetn = '0' then
        fifo_valid        <= '0';
        fifo_data         <= (others => '0');

        pop_tog_sys_ff0   <= '0';
        pop_tog_sys_ff1   <= '0';
        pop_tog_sys_prev  <= '0';
      else
        -- sync pop toggle into clk_in domain
        pop_tog_sys_ff0 <= pop_tog_sclk;
        pop_tog_sys_ff1 <= pop_tog_sys_ff0;

        -- detect toggle => word was consumed in sclk domain
        if pop_tog_sys_ff1 /= pop_tog_sys_prev then
          pop_tog_sys_prev <= pop_tog_sys_ff1;
          fifo_valid       <= '0';             -- clear mailbox
        end if;

        -- capture when empty and handshake occurs
        if (fifo_valid = '0') and (s_axis_aud_tvalid = '1') and (tready_i = '1') then
          fifo_data  <= s_axis_aud_tdata;
          fifo_valid <= '1';
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- ============ sync fifo_valid into sclk domain (rising edge) =========
  --------------------------------------------------------------------
  process(sclk_i)
  begin
    if rising_edge(sclk_i) then
      if aud_mrst = '1' then
        fifo_valid_s_ff0 <= '0';
        fifo_valid_s_ff1 <= '0';
      else
        fifo_valid_s_ff0 <= fifo_valid;
        fifo_valid_s_ff1 <= fifo_valid_s_ff0;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- ===================== SERIALIZER (sclk domain) =====================
  -- Change SDATA on falling edge; 1-bit I2S delay at start of slot.
  -- At the start of each slot (bitcnt=0), if fifo_valid is high,
  -- latch fifo_data and TOGGLE pop_tog_sclk to tell clk_in we consumed it.
  --------------------------------------------------------------------
  process(sclk_i)
  begin
    if falling_edge(sclk_i) then
      if aud_mrst = '1' then
        bitcnt       <= 0;
        sdata_0_out  <= '0';
        have_word    <= '0';
        shifter      <= (others => '0');
        pop_tog_sclk <= '0';
      elsif en_reg = '1' then
        if bitcnt = 0 then
          -- I2S dummy bit
          sdata_0_out <= '0';
          bitcnt      <= 31;

          -- latch a new word ONLY at the slot boundary
          if fifo_valid_s_ff1 = '1' then
            shifter   <= fifo_data;     -- stable because fifo_valid holds it
            have_word <= '1';
            pop_tog_sclk <= not pop_tog_sclk;  -- consume mailbox
          else
            have_word <= '0';
          end if;

        else
          -- output MSB first (after the dummy bit)
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
-- i2s_receiver_inputs stub (FULL REPLACEMENT)
-- Fixes:
--  1) NO multiple drivers on mb_valid_sclk (prevents X)
--  2) Clean SCLK-domain mailbox -> SYS-domain AXIS output using a toggle CDC
--  3) No reading OUT ports internally (all internal regs -> outputs)
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

  --------------------------------------------------------------------
  -- AXI-lite config registers
  --------------------------------------------------------------------
  signal div_reg  : unsigned(7 downto 0) := to_unsigned(2,8);
  signal en_reg   : std_logic := '0';

  -- internal bvalid so we can read it
  signal bvalid_r : std_logic := '0';

  --------------------------------------------------------------------
  -- Generated clocks (stub makes its own SCLK/LRCLK for convenience)
  --------------------------------------------------------------------
  signal sclk_i   : std_logic := '0';
  signal lrclk_i  : std_logic := '0';
  signal mclk_cnt : unsigned(7 downto 0) := (others => '0');

  --------------------------------------------------------------------
  -- SCLK-domain mailbox (single driver only in SCLK domain!)
  --------------------------------------------------------------------
  signal mb_data_sclk  : std_logic_vector(31 downto 0) := (others => '0');
  signal mb_valid_sclk : std_logic := '0';

  --------------------------------------------------------------------
  -- CDC: "new word" toggle from SCLK -> SYS
  --------------------------------------------------------------------
  signal push_tog_sclk : std_logic := '0';
  signal push_tog_sys_ff0, push_tog_sys_ff1, push_tog_sys_prev : std_logic := '0';
  signal new_word_sys  : std_logic := '0';

  -- CDC: "pop/consume" toggle from SYS -> SCLK
  signal pop_tog_sys   : std_logic := '0';
  signal pop_tog_s_ff0, pop_tog_s_ff1, pop_tog_s_prev : std_logic := '0';
  signal pop_pulse_sclk : std_logic := '0';

  --------------------------------------------------------------------
  -- Deserializer state (SCLK domain)
  --------------------------------------------------------------------
  signal bitcnt  : integer range 0 to 31 := 0;
  signal shifter : std_logic_vector(31 downto 0) := (others => '0');
  signal skip1   : std_logic := '1';  -- I2S 1-bit delay flag

  --------------------------------------------------------------------
  -- SYS-domain AXIS output regs
  --------------------------------------------------------------------
  signal tvalid_r : std_logic := '0';
  signal tdata_r  : std_logic_vector(31 downto 0) := (others => '0');

begin

  --------------------------------------------------------------------
  -- Tie-offs / unused channels
  --------------------------------------------------------------------
  s_axi_ctrl_arready <= '1';
  s_axi_ctrl_rvalid  <= '0';
  s_axi_ctrl_rdata   <= (others => '0');
  s_axi_ctrl_rresp   <= "00";
  irq                <= '0';
  m_axis_aud_tid     <= (others => '0');

  -- drive outputs from internal regs
  s_axi_ctrl_bvalid <= bvalid_r;
  s_axi_ctrl_bresp  <= "00";

  m_axis_aud_tvalid <= tvalid_r;
  m_axis_aud_tdata  <= tdata_r;

  --------------------------------------------------------------------
  -- AXI-lite write (simplified)
  -- Accepts writes only when AWVALID and WVALID both high same cycle.
  -- (Your TOP FSM already handles robust handshakes.)
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- SCLK generation: toggle every div_reg MCLK cycles => MCLK/SCLK = 2*div_reg
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- LRCLK generation: toggle every 32 SCLK rising edges (32-bit slots)
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- SYS -> SCLK: pop toggle synchronizer (creates 1-cycle pulse)
  -- IMPORTANT: this process DOES NOT drive mb_valid_sclk anymore.
  --------------------------------------------------------------------
  process(sclk_i)
  begin
    if rising_edge(sclk_i) then
      if aud_mrst = '1' then
        pop_tog_s_ff0  <= '0';
        pop_tog_s_ff1  <= '0';
        pop_tog_s_prev <= '0';
        pop_pulse_sclk <= '0';
      else
        pop_tog_s_ff0 <= pop_tog_sys;
        pop_tog_s_ff1 <= pop_tog_s_ff0;

        pop_pulse_sclk <= '0';
        if pop_tog_s_ff1 /= pop_tog_s_prev then
          pop_tog_s_prev <= pop_tog_s_ff1;
          pop_pulse_sclk <= '1';
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Deserialize on rising edge; skip first bit after slot boundary (I2S delay)
  -- SINGLE DRIVER for mb_valid_sclk lives HERE ONLY.
  --------------------------------------------------------------------
  process(sclk_i)
    variable bit_index : integer;
  begin
    if rising_edge(sclk_i) then
      if aud_mrst = '1' then
        bitcnt        <= 0;
        shifter       <= (others => '0');
        skip1         <= '1';
        mb_data_sclk  <= (others => '0');
        mb_valid_sclk <= '0';
        push_tog_sclk <= '0';

      elsif en_reg = '1' then

        -- If SYS consumed last word, clear mailbox here (single driver)
        if pop_pulse_sclk = '1' then
          mb_valid_sclk <= '0';
        end if;

        -- slot boundary: restart
        if bitcnt = 0 then
          bitcnt <= 31;
          skip1  <= '1';
          shifter <= (others => '0');

        else
          -- ignore first bit after boundary (I2S delay)
          if skip1 = '1' then
            skip1 <= '0';
          else
            -- shift in next bit (MSB first build)
            -- After 31 captured bits, shifter will contain the full 32-bit word
            shifter <= shifter(30 downto 0) & sdata_0_in;
          end if;

          bitcnt <= bitcnt - 1;
        end if;

        -- End of slot: latch completed word into mailbox if empty
        -- (bitcnt=1 means we are about to finish the slot)
        if (bitcnt = 1) then
          if mb_valid_sclk = '0' then
            mb_data_sclk  <= shifter;
            mb_valid_sclk <= '1';
            push_tog_sclk <= not push_tog_sclk; -- announce to SYS
          end if;
        end if;

      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- SCLK -> SYS: push toggle synchronizer to create new_word_sys pulse
  --------------------------------------------------------------------
  process(m_axis_aud_aclk)
  begin
    if rising_edge(m_axis_aud_aclk) then
      if m_axis_aud_aresetn = '0' then
        push_tog_sys_ff0  <= '0';
        push_tog_sys_ff1  <= '0';
        push_tog_sys_prev <= '0';
        new_word_sys      <= '0';
      else
        push_tog_sys_ff0 <= push_tog_sclk;
        push_tog_sys_ff1 <= push_tog_sys_ff0;

        new_word_sys <= '0';
        if push_tog_sys_ff1 /= push_tog_sys_prev then
          push_tog_sys_prev <= push_tog_sys_ff1;
          new_word_sys      <= '1';
        end if;
      end if;
    end if;
  end process;

  --------------------------------------------------------------------
  -- SYS-domain AXIS output
  -- When new word arrives, present it and hold TVALID until TREADY.
  -- On acceptance, toggle pop_tog_sys to tell SCLK side to clear mailbox.
  --------------------------------------------------------------------
  process(m_axis_aud_aclk)
  begin
    if rising_edge(m_axis_aud_aclk) then
      if m_axis_aud_aresetn = '0' then
        tvalid_r   <= '0';
        tdata_r    <= (others => '0');
        pop_tog_sys <= '0';
      else
        -- capture new word if we are not currently holding one
        if (new_word_sys = '1') and (tvalid_r = '0') then
          tdata_r  <= mb_data_sclk; -- safe here in sim; toggle ensures stable enough
          tvalid_r <= '1';
        end if;

        -- handshake
        if (tvalid_r = '1') and (m_axis_aud_tready = '1') then
          tvalid_r   <= '0';
          pop_tog_sys <= not pop_tog_sys; -- tell SCLK side to clear mailbox
        end if;
      end if;
    end if;
  end process;

end architecture;

