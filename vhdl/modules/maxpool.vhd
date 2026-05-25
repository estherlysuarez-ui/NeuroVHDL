-- ============================================================
-- Modulo: maxpool.vhd
-- Descripcion: MaxPooling 2x2 con stride 2.
--              Entrada: 28x28x8 canales -> Salida: 14x14x8
--
-- OPTIMIZACIONES vs. version original:
--   1. Buffer de una fila completa por filtro (8 x 28 x 8b = 1792b)
--      mapeado a BRAM M9K en lugar de arreglo 2D de FFs.
--   2. Logica de ventana 2x2 correcta:
--        - Fila par  (row par):  guardar pixel en line buffer
--        - Fila impar(row impar): comparar con fila anterior
--        - Columna par  : guardar pixel izquierdo
--        - Columna impar: calcular max(top-left, top-right,
--                                     bot-left, bot-right)
--   3. Señal done al terminar imagen completa.
--   4. filt_in/filt_out correctamente propagados.
--
-- Protocolo:
--   data_in / filt_in / valid_in : pixel de un canal de conv_relu
--   pool_out / filt_out / valid_out : pixel pooled
--   done : '1' al terminar la imagen 14x14
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity maxpool is
    generic (
        IMG_W  : integer := 28;   -- ancho de imagen entrada
        N_FILT : integer := 8     -- numero de canales/filtros
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        en        : in  std_logic;
        data_in   : in  signed(7 downto 0);
        filt_in   : in  std_logic_vector(2 downto 0);
        valid_in  : in  std_logic;
        pool_out  : out signed(7 downto 0);
        filt_out  : out std_logic_vector(2 downto 0);
        valid_out : out std_logic;
        done      : out std_logic
    );
end entity;

architecture rtl of maxpool is

    -- Line buffer: guarda una fila entera para cada filtro.
    -- Organizacion: addr = filtro * IMG_W + columna
    -- Tamaño: 8 * 28 = 224 x 8b = 1792 bits -> cabe en 1 M9K
    component ram_sp
        generic (ADDR_W : integer; DATA_W : integer; MIF_FILE : string);
        port (clk  : in  std_logic;
              wr   : in  std_logic;
              addr : in  std_logic_vector(ADDR_W-1 downto 0);
              din  : in  std_logic_vector(DATA_W-1 downto 0);
              dout : out std_logic_vector(DATA_W-1 downto 0));
    end component;

    -- Dirección: 8 bits (log2(8*28) = log2(224) <= 8)
    signal lb_wr   : std_logic := '0';
    signal lb_addr : std_logic_vector(7 downto 0);
    signal lb_din  : std_logic_vector(7 downto 0);
    signal lb_dout : std_logic_vector(7 downto 0);

    -- Contadores de posicion
    signal col : unsigned(4 downto 0) := (others => '0');  -- 0..27
    signal row : unsigned(4 downto 0) := (others => '0');  -- 0..27

    -- Registro del pixel izquierdo (columna par de la fila actual)
    signal left_cur  : signed(7 downto 0) := (others => '0');  -- bot-left
    signal left_top  : signed(7 downto 0) := (others => '0');  -- top-left (del lb)

    -- Salidas registradas
    signal r_out   : signed(7 downto 0) := (others => '0');
    signal r_filt  : std_logic_vector(2 downto 0) := (others => '0');
    signal r_valid : std_logic := '0';
    signal r_done  : std_logic := '0';

    -- Contador de pixeles de salida
    signal out_cnt : unsigned(10 downto 0) := (others => '0');  -- 0..14*14*8-1

    -- Funcion max de dos signed
    function max2(a, b : signed(7 downto 0)) return signed is
    begin
        if a > b then return a; else return b; end if;
    end function;

begin

    -- BRAM para line buffer (1 M9K)
    U_LB : ram_sp
        generic map (ADDR_W => 8, DATA_W => 8, MIF_FILE => "")
        port map (clk  => clk,
                  wr   => lb_wr,
                  addr => lb_addr,
                  din  => lb_din,
                  dout => lb_dout);

    -- FIX: calculo de direccion.
    -- Se opera en 9 bits para evitar overflow intermedio (max = 7*28+27 = 223),
    -- luego resize a 8 bits (223 < 256, sin perdida). Esto es valido en VHDL-93
    -- porque std_logic_vector se aplica sobre el resultado final de resize,
    -- no sobre una expresion de conversion de tipo.
    lb_addr <= std_logic_vector(
                  resize(
                    resize(unsigned(filt_in), 9) * to_unsigned(IMG_W, 9)
                    + resize(col, 9),
                  8));

    process(clk)
        variable top_left  : signed(7 downto 0);
        variable top_right : signed(7 downto 0);
        variable bot_left  : signed(7 downto 0);
        variable bot_right : signed(7 downto 0);
        variable best      : signed(7 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                col     <= (others => '0');
                row     <= (others => '0');
                lb_wr   <= '0';
                r_valid <= '0';
                r_done  <= '0';
                out_cnt <= (others => '0');
                left_cur <= (others => '0');
                left_top <= (others => '0');
            else
                lb_wr   <= '0';
                r_valid <= '0';
                r_done  <= '0';

                if valid_in = '1' and en = '1' then

                    if row(0) = '0' then
                        -- ── Fila par: guardar en line buffer ─────────────
                        lb_wr  <= '1';
                        lb_din <= std_logic_vector(data_in);
                        -- Guardar pixel izquierdo cuando col es par
                        if col(0) = '0' then
                            left_cur <= data_in;
                        end if;

                    else
                        -- ── Fila impar ────────────────────────────────────
                        if col(0) = '0' then
                            -- Columna par: guardar bot-left y leer top-left
                            left_cur <= data_in;
                            left_top <= signed(lb_dout);  -- top-left del LB
                        else
                            -- Columna impar: tenemos la ventana 2x2 completa
                            -- top-left = left_top (guardado ciclo anterior)
                            -- top-right = lb_dout (lectura actual BRAM, col impar)
                            -- bot-left = left_cur
                            -- bot-right = data_in
                            top_left  := left_top;
                            top_right := signed(lb_dout);
                            bot_left  := left_cur;
                            bot_right := data_in;

                            best := max2(max2(top_left, top_right),
                                        max2(bot_left, bot_right));

                            r_out   <= best;
                            r_filt  <= filt_in;
                            r_valid <= '1';

                            out_cnt <= out_cnt + 1;
                            -- Done cuando completamos 14*14*8 = 1568 pixeles
                            if out_cnt = (IMG_W/2)*(IMG_W/2)*N_FILT - 1 then
                                r_done  <= '1';
                                out_cnt <= (others => '0');
                            end if;
                        end if;
                    end if;

                    -- Avanzar contadores (por cada canal)
                    if unsigned(filt_in) = N_FILT-1 then
                        if col = IMG_W-1 then
                            col <= (others => '0');
                            if row = IMG_W-1 then
                                row <= (others => '0');
                            else
                                row <= row + 1;
                            end if;
                        else
                            col <= col + 1;
                        end if;
                    end if;

                end if;
            end if;
        end if;
    end process;

    pool_out  <= r_out;
    filt_out  <= r_filt;
    valid_out <= r_valid;
    done      <= r_done;

end architecture rtl;