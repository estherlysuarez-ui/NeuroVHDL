-- ============================================================
-- Componente: registro.vhd
-- Descripcion: Registro de N bits con enable y reset sincrono.
--              Usado como etapa de pipeline entre modulos.
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;

entity registro is
    generic (N : integer := 8);
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        en    : in  std_logic;
        d     : in  std_logic_vector(N-1 downto 0);
        q     : out std_logic_vector(N-1 downto 0)
    );
end entity;

architecture rtl of registro is
    signal r_q : std_logic_vector(N-1 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r_q <= (others => '0');
            elsif en = '1' then
                r_q <= d;
            end if;
        end if;
    end process;
    q <= r_q;
end architecture;
