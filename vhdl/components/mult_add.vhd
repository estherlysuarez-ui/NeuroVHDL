-- ============================================================
-- Componente: mult_add.vhd
-- Descripcion: Unidad Multiply-Accumulate (MAC) en Q1.7
--              optimizada para DSP embebido Cyclone IV (9x9).
--
--  Pipeline de 2 etapas:
--    Etapa 1: a * b  -> prod (registro)
--    Etapa 2: acc + prod >> FRAC  -> acc (registro)
--
--  Atributos multstyle="dsp" fuerzan inferencia DSP.
--  Un solo bloque DSP 9x9 de Cyclone IV cubre la operacion.
--
--  Latencia: 2 ciclos de reloj desde en='1' hasta acc valido.
--  clr limpia el acumulador al SIGUIENTE ciclo (sincrono).
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mult_add is
    port (
        clk   : in  std_logic;
        reset : in  std_logic;
        en    : in  std_logic;
        clr   : in  std_logic;                    -- limpia acumulador (sincrono)
        a     : in  signed(7 downto 0);           -- activacion Q1.7
        b     : in  signed(7 downto 0);           -- peso Q1.7
        acc   : out signed(23 downto 0)           -- acumulado sin truncar
    );
end entity;

architecture rtl of mult_add is

    -- Atributo para forzar inferencia DSP en Cyclone IV
    attribute multstyle : string;

    signal r_prod : signed(15 downto 0) := (others => '0');  -- etapa 1
    signal r_acc  : signed(23 downto 0) := (others => '0');  -- etapa 2

    -- El atributo se aplica a la senal del producto
    attribute multstyle of r_prod : signal is "dsp";

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                r_prod <= (others => '0');
                r_acc  <= (others => '0');
            else
                -- Etapa 1: registro del producto (inferencia DSP)
                if en = '1' then
                    r_prod <= a * b;
                end if;

                -- Etapa 2: acumulacion con clear sincrono
                if clr = '1' then
                    r_acc <= (others => '0');
                elsif en = '1' then
                    -- Suma el producto de la etapa anterior (pipeline)
                    r_acc <= r_acc + resize(r_prod, 24);
                end if;
            end if;
        end if;
    end process;

    acc <= r_acc;

end architecture;
