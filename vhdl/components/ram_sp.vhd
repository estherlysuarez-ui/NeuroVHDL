-- ============================================================
-- Componente: ram_sp.vhd
-- Descripcion: RAM single-port inferida en BRAM M9K de Cyclone IV.
--
--  Lectura registrada (1 ciclo latencia) -> modo read-during-write
--  "new data" para que Quartus infiera M9K en modo Simple Dual
--  o Single Port segun el uso.
--
--  Inicializacion con archivo .mif mediante atributo
--  ram_init_file (reconocido por Quartus II/Prime).
--
--  Configuraciones tipicas del proyecto:
--    Imagen entrada  : ADDR=10, DATA=8  (1024 x 8b = 1 M9K)
--    Activaciones FC : ADDR=11, DATA=8  (2048 x 8b = 1 M9K)
--    Pesos FC1       : ADDR=17, DATA=8  (131072 x 8b ~ 15 M9K)
--    Pesos FC2       : ADDR=10, DATA=8  (1024 x 8b = 1 M9K)
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_sp is
    generic (
        ADDR_W   : integer := 10;
        DATA_W   : integer := 8;
        MIF_FILE : string  := ""
    );
    port (
        clk  : in  std_logic;
        wr   : in  std_logic;
        addr : in  std_logic_vector(ADDR_W-1 downto 0);
        din  : in  std_logic_vector(DATA_W-1 downto 0);
        dout : out std_logic_vector(DATA_W-1 downto 0)
    );
end entity;

architecture rtl of ram_sp is

    type t_mem is array(0 to 2**ADDR_W - 1)
                  of std_logic_vector(DATA_W-1 downto 0);
    signal mem : t_mem := (others => (others => '0'));

    -- Atributo de inicializacion reconocido por Quartus II/Prime
    attribute ram_init_file : string;
    attribute ram_init_file of mem : signal is MIF_FILE;

    -- Forzar inferencia BRAM M9K (evitar que Quartus use LUT-RAM)
    attribute ramstyle : string;
    attribute ramstyle of mem : signal is "M9K";

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if wr = '1' then
                mem(to_integer(unsigned(addr))) <= din;
            end if;
            -- Lectura registrada: 1 ciclo de latencia
            -- (compatibilidad directa con M9K en modo registered output)
            dout <= mem(to_integer(unsigned(addr)));
        end if;
    end process;

end architecture;
