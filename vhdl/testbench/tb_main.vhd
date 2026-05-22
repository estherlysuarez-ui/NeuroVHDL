-- ============================================================
-- Testbench: tb_main.vhd
-- Descripcion: Testbench automatizado para la CNN MNIST completa.
--
-- Flujo de prueba (por cada imagen):
--   1. Reset del sistema
--   2. Carga de imagen pixel a pixel en la BRAM interna
--      (img_wr='1', img_addr=0..783, img_din=pixel)
--   3. Pulso start de 1 ciclo
--   4. Espera hasta que done='1'
--   5. Compara class_out con la etiqueta esperada
--   6. Acumula aciertos y reporta resultado por consola
--
-- Archivos de entrada (deben estar en el directorio de simulacion):
--   test_images.txt : 1 pixel por linea en binario (8 bits)
--                     784 lineas por imagen, N imagenes en total
--   test_labels.txt : 1 etiqueta por linea (decimal 0..9)
--
-- Estos archivos los genera training/train_and_export.py
--
-- Parametros configurables:
--   CLK_PERIOD  : periodo de reloj (10 ns = 100 MHz)
--   N_IMAGES    : numero de imagenes a probar (max 100)
--   TIMEOUT_CYC : ciclos maximos de espera por inferencia
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_main is
end entity;

architecture sim of tb_main is

    -- ── Parametros ───────────────────────────────────────────
    constant CLK_PERIOD  : time    := 10 ns;   -- 100 MHz
    constant N_IMAGES    : integer := 10;       -- imagenes a probar
    constant TIMEOUT_CYC : integer := 5_000_000; -- timeout por inferencia

    -- ── Senales DUT ──────────────────────────────────────────
    signal clk       : std_logic := '0';
    signal reset     : std_logic := '1';
    signal start     : std_logic := '0';
    signal img_wr    : std_logic := '0';
    signal img_addr  : std_logic_vector(9 downto 0) := (others => '0');
    signal img_din   : std_logic_vector(7 downto 0) := (others => '0');
    signal class_out : std_logic_vector(3 downto 0);
    signal valid_out : std_logic;
    signal done      : std_logic;
    signal state_dbg : std_logic_vector(7 downto 0);

    -- ── Componente DUT ───────────────────────────────────────
    component main
        port (
            clk       : in  std_logic;
            reset     : in  std_logic;
            start     : in  std_logic;
            img_wr    : in  std_logic;
            img_addr  : in  std_logic_vector(9 downto 0);
            img_din   : in  std_logic_vector(7 downto 0);
            class_out : out std_logic_vector(3 downto 0);
            valid_out : out std_logic;
            done      : out std_logic;
            state_dbg : out std_logic_vector(7 downto 0)
        );
    end component;

    -- ── Procedimientos auxiliares ─────────────────────────────

    -- Esperar N ciclos de reloj
    procedure wait_cycles(n : integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

begin

    -- ── Instancia DUT ────────────────────────────────────────
    DUT : main
        port map (
            clk       => clk,
            reset     => reset,
            start     => start,
            img_wr    => img_wr,
            img_addr  => img_addr,
            img_din   => img_din,
            class_out => class_out,
            valid_out => valid_out,
            done      => done,
            state_dbg => state_dbg
        );

    -- ── Generador de reloj ────────────────────────────────────
    clk <= not clk after CLK_PERIOD / 2;

    -- ── Proceso principal de estimulo ─────────────────────────
    process
        -- Archivos de entrada
        file f_images : text;
        file f_labels : text;
        variable line_img : line;
        variable line_lbl : line;

        -- Variables de lectura
        variable pix_slv  : std_logic_vector(7 downto 0);
        variable lbl_int  : integer;
        variable lbl_char : character;
        variable lbl_str  : string(1 to 2);  -- maximo "9\n"
        variable got_char : boolean;

        -- Estadisticas
        variable n_correct : integer := 0;
        variable n_total   : integer := 0;
        variable predicted : integer;
        variable timeout_cnt : integer;

        -- Para leer etiqueta como entero desde texto
        variable lbl_val : integer := 0;

    begin
        -- ── Reset inicial ─────────────────────────────────────
        reset <= '1';
        start <= '0';
        img_wr <= '0';
        wait_cycles(5);
        reset <= '0';
        wait_cycles(2);

        -- ── Abrir archivos ────────────────────────────────────
        file_open(f_images, "test_images.txt", read_mode);
        file_open(f_labels, "test_labels.txt", read_mode);

        report "================================================";
        report " TB CNN MNIST - Inicio de pruebas";
        report " Imagenes a probar: " & integer'image(N_IMAGES);
        report "================================================";

        -- ── Bucle principal: una inferencia por imagen ────────
        for img_i in 0 to N_IMAGES-1 loop

            -- ── 1. Reset del sistema ──────────────────────────
            reset <= '1';
            wait_cycles(3);
            reset <= '0';
            wait_cycles(2);

            -- ── 2. Cargar imagen en BRAM ──────────────────────
            img_wr <= '1';
            for px in 0 to 783 loop
                -- Leer siguiente linea del archivo de imagenes
                readline(f_images, line_img);
                read(line_img, pix_slv);

                img_addr <= std_logic_vector(to_unsigned(px, 10));
                img_din  <= pix_slv;
                wait until rising_edge(clk);
            end loop;
            img_wr <= '0';
            wait_cycles(2);

            -- ── 3. Pulso start ────────────────────────────────
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            -- ── 4. Esperar done con timeout ───────────────────
            timeout_cnt := 0;
            wait_loop : loop
                wait until rising_edge(clk);
                timeout_cnt := timeout_cnt + 1;
                exit wait_loop when done = '1';
                if timeout_cnt >= TIMEOUT_CYC then
                    report "TIMEOUT en imagen " & integer'image(img_i)
                           & " (estado FSM: " &
                           integer'image(to_integer(unsigned(state_dbg))) & ")"
                    severity warning;
                    exit wait_loop;
                end if;
            end loop;

            -- ── 5. Leer resultado ─────────────────────────────
            predicted := to_integer(unsigned(class_out));

            -- ── 6. Leer etiqueta esperada ─────────────────────
            readline(f_labels, line_lbl);
            -- Leer digito caracter a caracter
            lbl_val := 0;
            read_lbl : loop
                read(line_lbl, lbl_char, got_char);
                exit read_lbl when not got_char;
                if lbl_char >= '0' and lbl_char <= '9' then
                    lbl_val := lbl_val * 10 +
                               (character'pos(lbl_char) - character'pos('0'));
                end if;
            end loop;

            -- ── 7. Comparar y reportar ────────────────────────
            n_total := n_total + 1;
            if predicted = lbl_val then
                n_correct := n_correct + 1;
                report "Imagen " & integer'image(img_i) &
                       ": OK  | pred=" & integer'image(predicted) &
                       " | real=" & integer'image(lbl_val) &
                       " | ciclos=" & integer'image(timeout_cnt);
            else
                report "Imagen " & integer'image(img_i) &
                       ": FAIL| pred=" & integer'image(predicted) &
                       " | real=" & integer'image(lbl_val) &
                       " | ciclos=" & integer'image(timeout_cnt)
                severity warning;
            end if;

            wait_cycles(5);
        end loop;

        -- ── Cerrar archivos ───────────────────────────────────
        file_close(f_images);
        file_close(f_labels);

        -- ── Reporte final ─────────────────────────────────────
        report "================================================";
        report " RESULTADO FINAL";
        report " Correctas : " & integer'image(n_correct) &
               " / " & integer'image(n_total);
        report " Precision : " &
               integer'image((n_correct * 100) / n_total) & "%";
        report "================================================";

        -- Terminar simulacion
        assert false
            report "Simulacion completada."
            severity failure;

        wait;
    end process;

    -- ── Monitor: reportar transiciones de estado FSM ──────────
    process(state_dbg)
    begin
        case state_dbg is
            when "00000001" => -- S_IDLE
                null;
            when "00000010" =>
                report "[FSM] -> S_ENTRADA";
            when "00000100" =>
                report "[FSM] -> S_CONV";
            when "00001000" =>
                report "[FSM] -> S_POOL";
            when "00010000" =>
                report "[FSM] -> S_FC1";
            when "00100000" =>
                report "[FSM] -> S_OUT";
            when "01000000" =>
                report "[FSM] -> S_DONE";
            when "10000000" =>
                report "[FSM] -> S_ERR (ERROR!)" severity error;
            when others =>
                null;
        end case;
    end process;

end architecture;
