-- ============================================================
-- Componente: comparador.vhd
-- Descripcion: Comparador generico de N bits (signed).
--              Logica puramente combinacional -> 0 LUTs extra
--              sobre lo que el sintetizador ya usaria.
--
--   mayor : '1' si a > b
--   igual : '1' si a = b
--   relu  : max(0, a)  (util cuando N=8 para activaciones Q1.7)
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity comparador is
    generic (N : integer := 8);
    port (
        a     : in  signed(N-1 downto 0);
        b     : in  signed(N-1 downto 0);
        mayor : out std_logic;
        igual : out std_logic;
        relu  : out signed(N-1 downto 0)
    );
end entity;

architecture rtl of comparador is
begin
    -- Comparaciones combinacionales: el sintetizador usa la cadena
    -- de carry del bloque logico de Cyclone IV
    mayor <= '1' when a > b else '0';
    igual <= '1' when a = b else '0';

    -- ReLU = max(0, a): si el bit de signo es 1 -> negativo -> 0
    relu  <= a when a(N-1) = '0' else to_signed(0, N);

end architecture;
