-- ============================================================
-- Componente: ram_sp.vhd
-- Descripcion: RAM single-port sintetizable en BRAM M9K
--              (Cyclone IV). Usada para pesos de capas FC.
--              DATA=8 bits, ADDR=14 bits -> max 16384 bytes.
-- NOTA: inicializar con archivo .mif en Quartus (MIF_FILE).
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_sp is
    generic (
        ADDR_W   : integer := 14;         -- bits de direccion
        DATA_W   : integer := 8;          -- bits de dato
        MIF_FILE : string  := ""          -- archivo MIF (Quartus)
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

    -- Quartus reconoce este atributo para usar BRAM M9K
    attribute ram_init_file : string;
    attribute ram_init_file of mem : signal is MIF_FILE;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if wr = '1' then
                mem(to_integer(unsigned(addr))) <= din;
            end if;
            dout <= mem(to_integer(unsigned(addr)));
        end if;
    end process;
end architecture;
