-- ============================================================
-- Componente: relu_block.vhd
-- Descripcion:
--   Etapa final de la convolucion:
--
--      acumulador + bias + truncamiento + ReLU
--
-- Arquitectura:
--   - Recibe los 8 acumuladores de 24 bits
--   - Selecciona un filtro mediante filt_sel
--   - Suma bias correspondiente
--   - Convierte de 24 bits -> Q1.7
--   - Aplica ReLU
--
-- Entrada:
--   accX     : acumulador MAC del filtro X
--   biasX    : bias del filtro X
--   filt_sel : filtro seleccionado
--
-- Salida:
--   relu_out : salida final Q1.7
--
-- FPGA:
--   Cyclone IV
--
-- Formato:
--   Q1.7 signed
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity relu_block is
    generic (
        FRAC : integer := 7
    );
    port (

        -- ====================================================
        -- ENTRADAS ACUMULADORES
        -- ====================================================

        acc0 : in signed(23 downto 0);
        acc1 : in signed(23 downto 0);
        acc2 : in signed(23 downto 0);
        acc3 : in signed(23 downto 0);
        acc4 : in signed(23 downto 0);
        acc5 : in signed(23 downto 0);
        acc6 : in signed(23 downto 0);
        acc7 : in signed(23 downto 0);

        -- ====================================================
        -- BIASES
        -- ====================================================

        bias0 : in signed(7 downto 0);
        bias1 : in signed(7 downto 0);
        bias2 : in signed(7 downto 0);
        bias3 : in signed(7 downto 0);
        bias4 : in signed(7 downto 0);
        bias5 : in signed(7 downto 0);
        bias6 : in signed(7 downto 0);
        bias7 : in signed(7 downto 0);

        -- ====================================================
        -- FILTRO SELECCIONADO
        -- ====================================================

        filt_sel : in std_logic_vector(2 downto 0);

        -- ====================================================
        -- SALIDA FINAL
        -- ====================================================

        relu_out : out signed(7 downto 0)

    );
end entity;

architecture rtl of relu_block is

    -- ========================================================
    -- SEÑALES INTERNAS
    -- ========================================================

    signal sel_acc  : signed(23 downto 0);
    signal sel_bias : signed(7 downto 0);

begin

    -- ========================================================
    -- MULTIPLEXOR ACUMULADORES
    -- ========================================================

    with filt_sel select
        sel_acc <=
            acc0 when "000",
            acc1 when "001",
            acc2 when "010",
            acc3 when "011",
            acc4 when "100",
            acc5 when "101",
            acc6 when "110",
            acc7 when others;

    -- ========================================================
    -- MULTIPLEXOR BIAS
    -- ========================================================

    with filt_sel select
        sel_bias <=
            bias0 when "000",
            bias1 when "001",
            bias2 when "010",
            bias3 when "011",
            bias4 when "100",
            bias5 when "101",
            bias6 when "110",
            bias7 when others;

    -- ========================================================
    -- BLOQUE ReLU + BIAS + TRUNCAMIENTO
    -- ========================================================

    process(sel_acc, sel_bias)

        variable biased  : signed(23 downto 0);
        variable trunced : signed(7 downto 0);

    begin

        -- ====================================================
        -- SUMA BIAS
        -- ====================================================

        biased :=
            sel_acc
            +
            resize(sel_bias, 24);

        -- ====================================================
        -- TRUNCAMIENTO Q1.7
        -- ====================================================

        trunced :=
            biased(FRAC+7 downto FRAC);

        -- ====================================================
        -- ReLU
        -- ====================================================

        if biased(23) = '0' then
            relu_out <= trunced;
        else
            relu_out <= (others => '0');
        end if;

    end process;

end architecture;