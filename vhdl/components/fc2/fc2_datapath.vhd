-- ============================================================
-- Modulo: fc2_datapath.vhd (ESTABLE SIN LAZOS)
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fc2_datapath is
    port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        argmax_reset  : in  std_logic;
        argmax_update : in  std_logic;
        mac_en        : in  std_logic;
        
        mac_acc       : in  signed(23 downto 0);
        b_dout        : in  std_logic_vector(7 downto 0);
        cnt_neur_val  : in  std_logic_vector(3 downto 0);
        
        mac_en_d      : out std_logic;
        class_out     : out std_logic_vector(3 downto 0)
    );
end entity;

architecture rtl of fc2_datapath is
    constant MIN_SIGNED_24 : signed(23 downto 0) := (23 => '1', others => '0');
    signal biased_acc     : signed(23 downto 0);
    signal r_max_val      : signed(23 downto 0) := MIN_SIGNED_24;
    signal r_max_idx      : std_logic_vector(3 downto 0) := (others => '0');
begin

    -- Extensión de signo segura y suma combinacional del Bias
    biased_acc <= mac_acc + resize(signed(b_dout), 24);

    -- Registro síncrono del Argmax
    process(clk) begin
        if rising_edge(clk) then
            if reset = '1' or argmax_reset = '1' then
                r_max_val <= MIN_SIGNED_24;
                r_max_idx <= (others => '0');
            elsif argmax_update = '1' then
                if biased_acc > r_max_val then
                    r_max_val <= biased_acc;
                    r_max_idx <= cnt_neur_val;
                end if;
            end if;
        end if;
    end process;

    -- Salida directa registrada
    class_out <= r_max_idx;
    mac_en_d  <= mac_en; -- Bypass directo o herencia
end architecture;