-- ============================================================
-- Componente: mult_add.vhd
-- Descripcion: Unidad Multiply-Accumulate (MAC) en Q1.7.
--              acc = acc + (a * b) >> FRAC
--              a, b : signed 8-bit Q1.7
--              acc  : signed 24-bit (guarda acumulacion parcial)
-- Nota: un solo DSP en Cyclone IV cubre esta operacion.
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mult_add is
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        en    : in  std_logic;
        clr   : in  std_logic;                    -- limpia acumulador
        a     : in  signed(7 downto 0);           -- pixel / activacion Q1.7
        b     : in  signed(7 downto 0);           -- peso Q1.7
        acc   : out signed(23 downto 0)           -- acumulado (aun sin truncar)
    );
end entity;

architecture rtl of mult_add is
    signal r_acc : signed(23 downto 0) := (others => '0');
    signal prod  : signed(15 downto 0);
begin
    prod <= a * b;   -- 16 bits producto

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' or clr = '1' then
                r_acc <= (others => '0');
            elsif en = '1' then
                -- suma producto escalado a Q1.7 (>> 7)
                r_acc <= r_acc + resize(prod, 24);
            end if;
        end if;
    end process;

    acc <= r_acc;
end architecture;
