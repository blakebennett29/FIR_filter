-- tb_fir.vhd  (simulation-only testbench)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_fir is
end entity;

architecture sim of tb_fir is
  constant CLK_PERIOD : time := 125 us;  -- 8 kHz sample rate
  signal clk        : std_logic := '0';
  signal reset      : std_logic := '1';
  signal sample_in  : signed(23 downto 0) := (others => '0');
  signal sample_out : signed(47 downto 0);

  constant fs     : real := 8000.0;
  constant f_stim : real := 300.0;
  constant pi     : real := 3.141592653589793;
begin
  -- Clock
  clk_gen: process
  begin
    clk <= '0'; wait for CLK_PERIOD/2;
    clk <= '1'; wait for CLK_PERIOD/2;
  end process;

  -- Stimulus: 300 Hz full-scale sine, 1000 samples
  stim_proc: process
    variable L   : line;
    variable ang : real := 0.0;
  begin
    wait for 10*CLK_PERIOD;
    reset <= '0';

    for i in 0 to 999 loop
      ang := ang + 2.0*pi*f_stim/fs;
      if ang > 2.0*pi then
        ang := ang - 2.0*pi;
      end if;

      sample_in <= to_signed(integer(8388607.0 * sin(ang)), 24);
      wait for CLK_PERIOD;

      -- dump filtered output (as bits) to console
      ieee.std_logic_textio.write(
        L         => L,
        VALUE     => std_logic_vector(sample_out),
        JUSTIFIED => RIGHT,
        FIELD     => 0
      );
      writeline(output, L);
    end loop;

    wait;
  end process;

  -- DUT
  uut: entity fir_filter
    generic map (N_TAPS => 8)
    port map (
      clk        => clk,
      reset      => reset,
      sample_in  => sample_in,
      sample_out => sample_out
    );
end architecture;
