-- ============================================================
-- Componente: comparador.vhd
-- Descripcion: Comparador generico de N bits (signed).
--              Modos: mayor, menor, igual + ReLU inline.
--   mayor : a > b  -> mayor='1'
--   igual : a = b  -> igual='1'
--   relu  : max(0, a) en Q1.7 saturado a 127
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
        -- ReLU: solo cuando N=8 y se usa como activacion
        relu  : out signed(N-1 downto 0)
    );
end entity;

architecture rtl of comparador is
begin
    mayor <= '1' when a > b  else '0';
    igual <= '1' when a = b  else '0';
    -- ReLU: si negativo -> 0, si positivo -> a (ya saturado en MAC)
    relu  <= a when a > to_signed(0, N) else to_signed(0, N);
end architecture;
