library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity maxpool is
    generic (
        IMG_W  : integer := 28;
        N_FILT : integer := 8
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        data_in   : in  signed(7 downto 0);
        filt_in   : in  std_logic_vector(2 downto 0);
        valid_in  : in  std_logic;
        pool_out  : out signed(7 downto 0);
        filt_out  : out std_logic_vector(2 downto 0);
        valid_out : out std_logic
    );
end entity;

architecture rtl of maxpool is

    -- Guarda la fila de arriba mientras llega la fila de abajo
    type t_buf is array(0 to N_FILT-1, 0 to IMG_W-1) of signed(7 downto 0);
    signal buf : t_buf;

    signal col : unsigned(4 downto 0) := (others => '0');
    signal row : unsigned(4 downto 0) := (others => '0');
    signal prev : signed(7 downto 0); -- pixel anterior en la misma fila

begin

    process(clk)
        variable fi   : integer range 0 to N_FILT-1;
        variable c    : integer range 0 to IMG_W-1;
        variable top  : signed(7 downto 0);
        variable best : signed(7 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                col <= (others => '0');
                row <= (others => '0');
                valid_out <= '0';

            elsif valid_in = '1' then
                fi := to_integer(unsigned(filt_in));
                c  := to_integer(col);

                valid_out <= '0';

                if row(0) = '0' then
                    -- Fila par: solo guardar en buffer
                    buf(fi, c) <= data_in;
                else
                    -- Fila impar: tenemos la ventana completa cuando col es impar
                    if col(0) = '1' then
                        top  := buf(fi, c-1); -- fila de arriba, col anterior (ya en buf)

                        -- max de los 4: prev(fila arr izq), buf(fi,c)(fila arr der),
                        --               prev(fila abj izq), data_in(fila abj der)
                        -- Reutilizamos buf(fi,c-1) como top-left y buf guardado antes
                        if buf(fi, c-1) > buf(fi, c) then best := buf(fi, c-1);
                                                       else best := buf(fi, c); end if;
                        if prev         > best        then best := prev;        end if;
                        if data_in      > best        then best := data_in;     end if;

                        pool_out  <= best;
                        filt_out  <= filt_in;
                        valid_out <= '1';
                    end if;
                end if;

                -- Guardar pixel actual para usarlo como "col-1" en el proximo ciclo
                prev <= data_in;

                -- Contadores: avanzan con el ultimo canal
                if fi = N_FILT-1 then
                    if col = IMG_W-1 then
                        col <= (others => '0');
                        if row = IMG_W-1 then row <= (others => '0');
                                         else row <= row + 1; end if;
                    else
                        col <= col + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;