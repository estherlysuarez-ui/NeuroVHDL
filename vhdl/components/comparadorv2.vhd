-- ============================================================
-- Componente: comparador.vhd
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity comparadorv2 is
    generic (
        N : integer := 8
    );
    port (

        a : in signed(N-1 downto 0);
        b : in signed(N-1 downto 0);

        mayor : out std_logic;
        igual : out std_logic;

        max_out : out signed(N-1 downto 0);

        relu : out signed(N-1 downto 0)

    );
end entity;

architecture rtl of comparadorv2 is
begin

    mayor <= '1' when a > b else '0';

    igual <= '1' when a = b else '0';

    max_out <= a when a > b else b;

    relu <= a when a(N-1) = '0'
         else to_signed(0, N);

end architecture;