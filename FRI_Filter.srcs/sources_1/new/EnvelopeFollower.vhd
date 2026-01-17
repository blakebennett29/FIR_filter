library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================
-- Envelope follower (per band)
-- 1) r = abs(x)  (full-wave rectify)
-- 2) e += (r - e) >> k   (k depends on attack/decay)
-- ============================================================
entity envelope_follower is
  generic (
    DATA_W       : positive := 24;  -- signed input width (FIR output)
    ENV_W        : positive := 24;  -- envelope output width (unsigned)
    ATTACK_SHIFT : natural  := 5;   -- alpha_a = 2^-ATTACK_SHIFT (fast rise)
    DECAY_SHIFT  : natural  := 9    -- alpha_d = 2^-DECAY_SHIFT  (slow fall)
  );
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;  -- synchronous active-high reset

    sample_in   : in  signed(DATA_W-1 downto 0);
    sample_valid: in  std_logic;  -- pulse/high when sample_in is valid

    env_out     : out unsigned(ENV_W-1 downto 0);
    env_valid   : out std_logic   -- pulse/high when env_out updated
  );
end entity;

architecture rtl of envelope_follower is
  signal env_reg : unsigned(ENV_W-1 downto 0) := (others => '0');

  -- Rectified magnitude in a wider type to avoid overflow during abs()
  -- We keep one extra bit for safety during intermediate math.
  signal rect_mag : unsigned(DATA_W downto 0);
begin

  -- Full-wave rectify (combinational)
  -- Note: abs(signed) overflows on the most-negative value; we saturate that case.
  process(sample_in)
    variable x      : signed(DATA_W-1 downto 0);
    variable mag_s  : signed(DATA_W downto 0);
    variable sat_u  : unsigned(DATA_W downto 0);
  begin
    x := sample_in;

    if x = to_signed(-2**(DATA_W-1), DATA_W) then
      -- Saturate: abs(min_neg) cannot be represented in DATA_W bits
      sat_u := to_unsigned(2**(DATA_W-1)-1, DATA_W+1);
      rect_mag <= sat_u;
    elsif x(DATA_W-1) = '1' then
      mag_s := resize(-x, DATA_W+1);
      rect_mag <= unsigned(mag_s);
    else
      mag_s := resize(x, DATA_W+1);
      rect_mag <= unsigned(mag_s);
    end if;
  end process;

  -- Envelope update (registered)
  process(clk)
    variable r_env   : unsigned(ENV_W-1 downto 0);
    variable r_wide  : unsigned(ENV_W downto 0);
    variable e_wide  : unsigned(ENV_W downto 0);
    variable diff_u  : unsigned(ENV_W downto 0);
    variable step_u  : unsigned(ENV_W downto 0);
    variable next_e  : unsigned(ENV_W downto 0);
    variable k       : natural;
  begin
    if rising_edge(clk) then
      env_valid <= '0';

      if rst = '1' then
        env_reg   <= (others => '0');
        env_valid <= '0';

      elsif sample_valid = '1' then
        -- Resize rect_mag down/up to ENV_W
        -- If DATA_W+1 > ENV_W, we truncate MSBs (keep LSBs) which is typical if
        -- your FIR output is already scaled. If you prefer saturation, we can add it.
        r_env  := resize(rect_mag, ENV_W);   -- numeric_std resize handles trunc/extend
        r_wide := resize(r_env, ENV_W+1);
        e_wide := resize(env_reg, ENV_W+1);

        -- Choose attack/decay rate based on direction
        if r_wide > e_wide then
          k := ATTACK_SHIFT;
          diff_u := r_wide - e_wide;
          step_u := shift_right(diff_u, k);
          next_e := e_wide + step_u;
        else
          k := DECAY_SHIFT;
          diff_u := e_wide - r_wide;
          step_u := shift_right(diff_u, k);
          next_e := e_wide - step_u;
        end if;

        -- Saturate to ENV_W max (safety)
        if next_e(ENV_W) = '1' then
          env_reg <= (others => '1');
        else
          env_reg <= next_e(ENV_W-1 downto 0);
        end if;

        env_valid <= '1';
      end if;
    end if;
  end process;

  env_out <= env_reg;

end architecture;
