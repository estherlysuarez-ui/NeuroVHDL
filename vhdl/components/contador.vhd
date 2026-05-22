-- ============================================================
-- Componente: contador.vhd
-- Descripcion: Contador up generico con enable, reset sincrono
--              y flag de terminacion (done).
--              Reutilizado en todos los modulos del sistema.
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity contador is
    generic (
        N   : integer := 8;    -- bits del contador
        MAX : integer := 255   -- valor maximo (cuenta 0..MAX)
    );
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        en    : in  std_logic;
        cnt   : out std_logic_vector(N-1 downto 0);
        done  : out std_logic   -- '1' un ciclo cuando llega a MAX
    );
end entity;

architecture rtl of contador is
    signal r_cnt : unsigned(N-1 downto 0) := (others => '0');
begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r_cnt <= (others => '0');
            elsif en = '1' then
                if r_cnt = to_unsigned(MAX, N) then
                    r_cnt <= (others => '0');
                else
                    r_cnt <= r_cnt + 1;
                end if;
            end if;
        end if;
    end process;

    cnt  <= std_logic_vector(r_cnt);
    done <= '1' when (en = '1' and r_cnt = to_unsigned(MAX, N)) else '0';

end architecture;
