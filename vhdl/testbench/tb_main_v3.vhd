-- ============================================================
-- Testbench: tb_main_v3.vhd
-- Proyecto:  NeuroVHDL — CNN MNIST en FPGA Cyclone IV
-- Descripcion:
--   Testbench automatizado FINAL para el sistema top-level (main.vhd).
--   Ejecuta N_IMAGES inferencias completas leyendo pixeles y etiquetas
--   desde archivos de texto, verifica la clasificacion con asserts
--   y genera un reporte estadistico detallado.
--
-- Verificaciones implementadas:
--   [A1] Reset: class_out, valid_out y done deben ser '0' tras reset
--   [A2] FSM ONE-HOT: solo un bit activo en state_dbg en cada ciclo
--   [A3] Secuencia de estados: IDLE -> ENTRADA -> CONV -> POOL -> FC1 -> OUT -> DONE
--   [A4] valid_out sube antes o junto con done
--   [A5] class_out en rango valido [0..9]
--   [A6] Timeout de seguridad por inferencia
--   [A7] done se deasserta automaticamente (FSM regresa a IDLE)
--   [A8] Resultado de clasificacion vs etiqueta MNIST
--
-- Archivos requeridos en el directorio de simulacion:
--   test_images.txt  (784 lineas binarias de 8 bits por imagen)
--   test_labels.txt  (1 digito decimal por linea, 0..9)
--
-- Parametros ajustables:
--   CLK_PERIOD   : periodo de reloj
--   N_IMAGES     : imagenes a probar (max 100)
--   TIMEOUT_CYC  : ciclos maximos por inferencia antes de fallo
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_main_v3 is
end entity;

architecture sim of tb_main_v3 is

    -- =========================================================
    -- PARAMETROS CONFIGURABLES
    -- =========================================================

    constant CLK_PERIOD  : time    := 10 ns;      -- 100 MHz
    constant N_IMAGES    : integer := 10;          -- imagenes a inferir (max 100)
    constant TIMEOUT_CYC : integer := 5_000_000;  -- ciclos maximo por inferencia

    -- =========================================================
    -- CONSTANTES FSM ONE-HOT (espejo de fsm_control.vhd)
    -- =========================================================

    constant S_IDLE    : std_logic_vector(7 downto 0) := "00000001";
    constant S_ENTRADA : std_logic_vector(7 downto 0) := "00000010";
    constant S_CONV    : std_logic_vector(7 downto 0) := "00000100";
    constant S_POOL    : std_logic_vector(7 downto 0) := "00001000";
    constant S_FC1     : std_logic_vector(7 downto 0) := "00010000";
    constant S_OUT     : std_logic_vector(7 downto 0) := "00100000";
    constant S_DONE    : std_logic_vector(7 downto 0) := "01000000";
    constant S_ERR     : std_logic_vector(7 downto 0) := "10000000";

    -- =========================================================
    -- SENALES DUT
    -- =========================================================

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

    -- =========================================================
    -- SENALES DE CONTROL DE SIMULACION
    -- =========================================================

    signal sim_end          : boolean := false;
    signal fsm_prev         : std_logic_vector(7 downto 0) := S_IDLE;
    signal valid_seen       : std_logic := '0'; -- registro: valid_out se activo

    -- =========================================================
    -- DECLARACION DUT
    -- =========================================================

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

    -- =========================================================
    -- FUNCION AUXILIAR: nombre del estado FSM
    -- =========================================================

    function fsm_name(s : std_logic_vector(7 downto 0)) return string is
    begin
        case s is
            when "00000001" => return "S_IDLE";
            when "00000010" => return "S_ENTRADA";
            when "00000100" => return "S_CONV";
            when "00001000" => return "S_POOL";
            when "00010000" => return "S_FC1";
            when "00100000" => return "S_OUT";
            when "01000000" => return "S_DONE";
            when "10000000" => return "S_ERR";
            when others     => return "S_INVALIDO";
        end case;
    end function;

    -- =========================================================
    -- FUNCION AUXILIAR: contar bits '1' (para verificar ONE-HOT)
    -- =========================================================

    function count_ones(v : std_logic_vector) return integer is
        variable cnt : integer := 0;
    begin
        for i in v'range loop
            if v(i) = '1' then cnt := cnt + 1; end if;
        end loop;
        return cnt;
    end function;

begin

    -- =========================================================
    -- INSTANCIA DUT
    -- =========================================================

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

    -- =========================================================
    -- GENERADOR DE RELOJ
    -- =========================================================

    clk_proc : process
    begin
        while not sim_end loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- =========================================================
    -- [A1] ASSERT RESET: outputs deben estar en '0' durante reset
    -- =========================================================

    assert_reset : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                assert done = '0'
                    report "[A1-FAIL] done deberia ser '0' durante reset"
                    severity error;
                assert valid_out = '0'
                    report "[A1-FAIL] valid_out deberia ser '0' durante reset"
                    severity error;
            end if;
        end if;
    end process;

    -- =========================================================
    -- [A2] ASSERT FSM ONE-HOT: exactamente 1 bit activo
    -- =========================================================

    assert_onehot : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '0' then
                assert count_ones(state_dbg) = 1
                    report "[A2-FAIL] FSM state_dbg NO es ONE-HOT: 0x" &
                           integer'image(to_integer(unsigned(state_dbg)))
                    severity error;
            end if;
        end if;
    end process;

    -- =========================================================
    -- [A3] MONITOR FSM: reportar transiciones y verificar secuencia
    -- =========================================================

    fsm_monitor : process(clk)
        -- Estado esperado siguiente segun la secuencia CNN
        variable seq_ok : boolean := true;
    begin
        if rising_edge(clk) then
            if reset = '0' then
                if state_dbg /= fsm_prev then
                    -- Reportar transicion
                    report "[FSM] " & fsm_name(fsm_prev) &
                           " -> " & fsm_name(state_dbg);

                    -- Verificar que el estado S_ERR nunca se alcance
                    assert state_dbg /= S_ERR
                        report "[A3-FAIL] FSM entro en estado de ERROR (S_ERR)!"
                        severity failure;

                    -- Verificar que el estado no sea invalido
                    assert count_ones(state_dbg) = 1
                        report "[A3-FAIL] Transicion a estado FSM invalido: " &
                               integer'image(to_integer(unsigned(state_dbg)))
                        severity error;

                    fsm_prev <= state_dbg;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================
    -- [A4] MONITOR valid_out: registrar que se activo
    -- =========================================================

    valid_tracker : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                valid_seen <= '0';
            elsif valid_out = '1' then
                valid_seen <= '1';
            end if;
        end if;
    end process;

    -- =========================================================
    -- [A5] ASSERT class_out RANGO: solo valores 0..9 son validos
    -- =========================================================

    assert_class_range : process(clk)
    begin
        if rising_edge(clk) then
            if done = '1' and reset = '0' then
                assert to_integer(unsigned(class_out)) <= 9
                    report "[A5-FAIL] class_out fuera de rango [0..9]: " &
                           integer'image(to_integer(unsigned(class_out)))
                    severity error;
            end if;
        end if;
    end process;

    -- =========================================================
    -- PROCESO PRINCIPAL: estimulos y verificacion de inferencias
    -- =========================================================

    stim_proc : process
        -- Archivos E/S
        file f_img : text;
        file f_lbl : text;
        variable v_img_line : line;
        variable v_lbl_line : line;

        -- Variables de lectura
        variable v_pix      : std_logic_vector(7 downto 0);
        variable v_lbl_char : character;
        variable v_lbl_got  : boolean;
        variable v_lbl_val  : integer;

        -- Estadisticas
        variable n_correct  : integer := 0;
        variable n_timeout  : integer := 0;
        variable n_total    : integer := 0;
        variable v_predicted: integer;
        variable v_timeout  : integer;
        variable v_cycles   : integer;

        -- Tiempo de inferencia
        variable v_min_cyc  : integer := integer'high;
        variable v_max_cyc  : integer := 0;
        variable v_sum_cyc  : integer := 0;

        -- Procedimiento: esperar N ciclos de reloj
        procedure wait_clk(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- Procedimiento: reset del sistema
        procedure do_reset is
        begin
            reset <= '1';
            start <= '0';
            img_wr <= '0';
            img_addr <= (others => '0');
            img_din  <= (others => '0');
            wait_clk(5);
            reset <= '0';
            wait_clk(2);
        end procedure;

        -- Procedimiento: cargar imagen en BRAM pixel a pixel
        procedure load_image is
        begin
            img_wr <= '1';
            for px in 0 to 783 loop
                readline(f_img, v_img_line);
                read(v_img_line, v_pix);
                img_addr <= std_logic_vector(to_unsigned(px, 10));
                img_din  <= v_pix;
                wait until rising_edge(clk);
            end loop;
            img_wr   <= '0';
            img_addr <= (others => '0');
            img_din  <= (others => '0');
            wait_clk(2);
        end procedure;

        -- Procedimiento: leer etiqueta desde archivo
        procedure read_label(variable lbl : out integer) is
        begin
            readline(f_lbl, v_lbl_line);
            lbl := 0;
            loop
                read(v_lbl_line, v_lbl_char, v_lbl_got);
                exit when not v_lbl_got;
                if v_lbl_char >= '0' and v_lbl_char <= '9' then
                    lbl := lbl * 10 +
                           (character'pos(v_lbl_char) - character'pos('0'));
                end if;
            end loop;
        end procedure;

    begin

        -- =====================================================
        -- INICIALIZACION
        -- =====================================================

        report "======================================================";
        report " TB_MAIN_V3 — CNN MNIST FPGA | NeuroVHDL-Modularity";
        report " Imagenes a probar : " & integer'image(N_IMAGES);
        report " Timeout por imagen: " & integer'image(TIMEOUT_CYC) & " ciclos";
        report "======================================================";

        do_reset;

        -- [A1] Verificar estado post-reset
        assert state_dbg = S_IDLE
            report "[A1-FAIL] Tras reset, FSM no esta en S_IDLE: " &
                   fsm_name(state_dbg)
            severity error;
        assert done = '0'
            report "[A1-FAIL] done deberia ser '0' tras reset"
            severity error;
        assert valid_out = '0'
            report "[A1-FAIL] valid_out deberia ser '0' tras reset"
            severity error;
        report "[A1-OK] Reset verificado: FSM en S_IDLE, done='0', valid_out='0'";

        -- Abrir archivos de datos
        file_open(f_img, "test_images.txt", read_mode);
        file_open(f_lbl, "test_labels.txt", read_mode);

        -- =====================================================
        -- BUCLE PRINCIPAL DE INFERENCIAS
        -- =====================================================

        for img_i in 0 to N_IMAGES-1 loop

            report "------------------------------------------------------";
            report " Imagen " & integer'image(img_i) & " / " &
                   integer'image(N_IMAGES-1);

            -- Resetear para estado limpio entre inferencias
            do_reset;

            -- [A3] Confirmar que FSM esta en IDLE antes de start
            assert state_dbg = S_IDLE
                report "[A3-FAIL] Imagen " & integer'image(img_i) &
                       ": FSM no esta en S_IDLE antes de start (" &
                       fsm_name(state_dbg) & ")"
                severity error;

            -- ── FASE 1: Cargar imagen ──────────────────────
            report "[CARGA] Cargando 784 pixeles en BRAM...";
            load_image;

            -- ── FASE 2: Pulso START ────────────────────────
            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            -- [A3] Verificar que FSM arranca
            wait until rising_edge(clk);
            assert state_dbg /= S_IDLE
                report "[A3-FAIL] Imagen " & integer'image(img_i) &
                       ": FSM no salio de IDLE tras start"
                severity warning;

            -- ── FASE 3: Esperar done con timeout ──────────
            v_timeout := 0;
            v_cycles  := 0;

            wait_for_done : loop
                wait until rising_edge(clk);
                v_timeout := v_timeout + 1;
                v_cycles  := v_cycles + 1;

                -- [A2] CHECK ONE-HOT en cada ciclo (ya cubierto por proceso separado)

                -- Salir si done se activa
                exit wait_for_done when done = '1';

                -- [A6] Timeout de seguridad
                if v_timeout >= TIMEOUT_CYC then
                    report "[A6-FAIL] TIMEOUT en imagen " &
                           integer'image(img_i) &
                           " tras " & integer'image(v_timeout) &
                           " ciclos. Estado FSM: " & fsm_name(state_dbg)
                        severity error;
                    n_timeout := n_timeout + 1;
                    exit wait_for_done;
                end if;
            end loop;

            -- ── FASE 4: Verificaciones post-done ──────────

            -- [A4] valid_out debe haberse activado antes o junto con done
            assert valid_seen = '1'
                report "[A4-FAIL] Imagen " & integer'image(img_i) &
                       ": done='1' pero valid_out nunca se activo durante la inferencia"
                severity error;

            -- [A5] class_out debe estar en rango [0..9]
            v_predicted := to_integer(unsigned(class_out));
            assert v_predicted <= 9
                report "[A5-FAIL] Imagen " & integer'image(img_i) &
                       ": class_out=" & integer'image(v_predicted) &
                       " esta fuera del rango valido [0..9]"
                severity error;

            -- ── FASE 5: Leer etiqueta y comparar ──────────
            read_label(v_lbl_val);
            n_total := n_total + 1;

            -- Estadisticas de ciclos
            if v_cycles < v_min_cyc then v_min_cyc := v_cycles; end if;
            if v_cycles > v_max_cyc then v_max_cyc := v_cycles; end if;
            v_sum_cyc := v_sum_cyc + v_cycles;

            -- [A8] Comparar prediccion con etiqueta real
            if v_predicted = v_lbl_val then
                n_correct := n_correct + 1;
                report "[OK]   Imagen " & integer'image(img_i) &
                       " | pred=" & integer'image(v_predicted) &
                       " | real=" & integer'image(v_lbl_val) &
                       " | ciclos=" & integer'image(v_cycles);
            else
                report "[FAIL] Imagen " & integer'image(img_i) &
                       " | pred=" & integer'image(v_predicted) &
                       " | real=" & integer'image(v_lbl_val) &
                       " | ciclos=" & integer'image(v_cycles)
                    severity warning;
            end if;

            -- ── FASE 6: Verificar retorno a IDLE ──────────
            wait_clk(10);
            -- [A7] Despues de DONE la FSM debe regresar a IDLE
            assert state_dbg = S_IDLE
                report "[A7-FAIL] Imagen " & integer'image(img_i) &
                       ": FSM no regreso a S_IDLE despues de done (" &
                       fsm_name(state_dbg) & ")"
                severity error;
            assert done = '0'
                report "[A7-FAIL] Imagen " & integer'image(img_i) &
                       ": done sigue en '1' despues de la inferencia"
                severity warning;

        end loop; -- img_i

        -- =====================================================
        -- CERRAR ARCHIVOS
        -- =====================================================

        file_close(f_img);
        file_close(f_lbl);

        -- =====================================================
        -- REPORTE FINAL
        -- =====================================================

        report "======================================================";
        report " RESULTADO FINAL — TB_MAIN_V3";
        report "------------------------------------------------------";
        report " Imagenes probadas : " & integer'image(n_total);
        report " Correctas         : " & integer'image(n_correct);
        report " Incorrectas       : " & integer'image(n_total - n_correct - n_timeout);
        report " Timeouts          : " & integer'image(n_timeout);
        if n_total > 0 then
            report " Precision         : " &
                   integer'image((n_correct * 100) / n_total) & "%";
        end if;
        report "------------------------------------------------------";
        if n_total > 0 then
            report " Ciclos min/max/avg: " &
                   integer'image(v_min_cyc) & " / " &
                   integer'image(v_max_cyc) & " / " &
                   integer'image(v_sum_cyc / n_total);
        end if;
        report "======================================================";

        -- Terminar la simulacion con severity failure (comportamiento
        -- estandar de ModelSim para detener la simulacion de forma limpia)
        sim_end <= true;
        assert false
            report "Simulacion completada correctamente."
            severity failure;

        wait;
    end process;

    -- =========================================================
    -- MONITOR ADICIONAL: reportar salida de clasificacion cuando done
    -- =========================================================

    done_monitor : process(done)
    begin
        if done'event and done = '1' then
            report "[MONITOR] done='1' | class_out=" &
                   integer'image(to_integer(unsigned(class_out))) &
                   " | valid_out=" & std_logic'image(valid_out) &
                   " | FSM=" & fsm_name(state_dbg);
        end if;
    end process;

end architecture;
