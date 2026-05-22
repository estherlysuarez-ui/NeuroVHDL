-- ============================================================
-- Modulo: entrada.vhd
-- Descripcion: Lee pixeles de la BRAM de imagen (28x28 = 784px)
--              y los sirve al modulo conv_relu pixel a pixel.
--
-- Correccion vs. original:
--   - done generado correctamente cuando AMBOS contadores
--     estan en su valor maximo en el MISMO ciclo (no AND de
--     dos senales done separadas que pueden tener retardos).
--   - Lectura BRAM: addr se presenta un ciclo antes para
--     compensar la latencia registrada de ram_sp (M9K).
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity entrada is
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;
        -- Interfaz BRAM imagen (inicializada externamente)
        addr      : out std_logic_vector(9 downto 0);
        rd_en     : out std_logic;
        pixel_in  : in  std_logic_vector(7 downto 0);
        -- Salida al modulo conv_relu
        pixel_out : out signed(7 downto 0);
        valid_out : out std_logic;
        done      : out std_logic
    );
end entity;

architecture rtl of entrada is

    signal cnt_pix : unsigned(9 downto 0) := (others => '0');  -- 0..783

    signal r_addr  : unsigned(9 downto 0) := (others => '0');
    signal r_valid : std_logic := '0';
    signal r_done  : std_logic := '0';

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                cnt_pix <= (others => '0');
                r_addr  <= (others => '0');
                r_valid <= '0';
                r_done  <= '0';
            else
                r_valid <= '0';
                r_done  <= '0';

                if en = '1' then
                    -- Presentar direccion (el dato llega el siguiente ciclo de BRAM)
                    r_addr  <= cnt_pix;
                    r_valid <= '1';  -- el pixel en pixel_out es del ciclo anterior

                    if cnt_pix = 783 then
                        cnt_pix <= (others => '0');
                        r_done  <= '1';
                    else
                        cnt_pix <= cnt_pix + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    addr      <= std_logic_vector(r_addr);
    rd_en     <= en;
    -- pixel_out usa el dout de BRAM directamente (ya registrado en ram_sp)
    pixel_out <= signed(pixel_in);
    valid_out <= r_valid;
    done      <= r_done;

end architecture;
