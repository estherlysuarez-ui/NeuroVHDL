-- ============================================================
-- Testbench: tb_main_v2.vhd
-- Proyecto:  NeuroVHDL -- CNN MNIST en FPGA Cyclone IV
-- Rama:      Modularity
-- Autor:     Generado automaticamente para revision completa
--
-- DESCRIPCION GENERAL
-- -------------------
-- Testbench automatizado de cobertura total para el sistema CNN
-- que implementa reconocimiento de digitos MNIST. Verifica:
--
--   1. Secuencia de reset y arranque del sistema
--   2. Carga de imagen en BRAM interna pixel a pixel
--   3. Activacion de la FSM mediante pulso start
--   4. Secuencia ONE-HOT de estados FSM:
--        IDLE -> ENTRADA -> CONV -> POOL -> FC1 -> OUT -> DONE
--   5. Tiempo de inferencia por imagen (ciclos reales)
--   6. Precision de clasificacion vs etiquetas MNIST
--   7. Timeout de seguridad con reporte de estado FSM
--   8. Comportamiento tras multiples inferencias consecutivas
--   9. Test de reset durante inferencia activa
--  10. Resumen estadistico final automatizado
--
-- ARCHIVOS REQUERIDOS (en directorio de simulacion):
--   test_images.txt  -- pixeles en binario (8b por linea, 784 x N)
--   test_labels.txt  -- etiquetas decimales (0..9, una por linea)
--
-- PARAMETROS CONFIGURABLES:
--   CLK_PERIOD   : periodo de reloj (10 ns = 100 MHz)
--   N_IMAGES     : numero de imagenes a inferir (max 100)
--   TIMEOUT_CYC  : ciclos maximos de espera por inferencia
--   DO_RESET_TEST: activar test de reset en caliente
--
-- COMPATIBILIDAD:
--   ModelSim Altera Starter Edition 10.x+
--   GHDL 0.36+
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_main_v2 is
end entity;

architecture sim of tb_main_v2 is

    -- =========================================================
    -- PARAMETROS CONFIGURABLES
    -- =========================================================

    constant CLK_PERIOD   : time    := 10 ns;    -- 100 MHz
    constant N_IMAGES     : integer := 10;        -- imagenes a probar (max 100)
    constant TIMEOUT_CYC  : integer := 5_000_000; -- 50 ms a 100 MHz por inferencia
    constant DO_RESET_TEST: boolean := true;      -- test de reset en caliente

    -- =========================================================
    -- SENALES DUT (Device Under Test)
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
    -- SENALES DE MONITOREO INTERNO
    -- =========================================================

    signal fsm_state_prev : std_logic_vector(7 downto 0) := (others => '0');
    signal sim_done       : std_logic := '0';
    signal inferencia_ok  : std_logic := '0';

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
    -- PROCEDIMIENTOS AUXILIARES
    -- =========================================================

    -- Esperar N flancos de subida del reloj
    procedure wait_clk(n : integer) is
    begin
        for i in 1 to n loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    -- Nombre legible del estado ONE-HOT
    function fsm_state_name(s : std_logic_vector(7 downto 0)) return string is
    begin
        case s is
            when "00000001" => return "S_IDLE   ";
            when "00000010" => return "S_ENTRADA";
            when "00000100" => return "S_CONV   ";
            when "00001000" => return "S_POOL   ";
            when "00010000" => return "S_FC1    ";
            when "00100000" => return "S_OUT    ";
            when "01000000" => return "S_DONE   ";
            when "10000000" => return "S_ERR    ";
            when others     => return "UNKNOWN  ";
        end case;
    end function;

    -- Convertir std_logic_vector a string de '0'/'1'
    function slv_to_str(s : std_logic_vector) return string is
        variable result : string(1 to s'length);
    begin
        for i in s'range loop
            if s(i) = '1' then
                result(s'length - i) := '1';
            else
                result(s'length - i) := '0';
            end if;
        end loop;
        return result;
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
    -- GENERADOR DE RELOJ (100 MHz)
    -- =========================================================

    clk_gen : process
    begin
        while sim_done = '0' loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- =========================================================
    -- PROCESO PRINCIPAL DE ESTIMULO Y VERIFICACION
    -- =========================================================

    main_stimulus : process

        -- Archivos de entrada
        file   f_images : text;
        file   f_labels : text;
        variable line_img : line;
        variable line_lbl : line;

        -- Variables de lectura pixel
        variable pix_slv   : std_logic_vector(7 downto 0);

        -- Variables de lectura etiqueta
        variable lbl_char  : character;
        variable got_char  : boolean;
        variable lbl_val   : integer;

        -- Estadisticas acumuladas
        variable n_total     : integer := 0;
        variable n_correct   : integer := 0;
        variable n_timeout   : integer := 0;
        variable predicted   : integer;
        variable timeout_cnt : integer;

        -- Ciclos min/max
        variable min_cycles  : integer := integer'high;
        variable max_cycles  : integer := 0;
        variable sum_cycles  : integer := 0;

        -- Bandera error FSM
        variable fsm_error   : boolean := false;

    begin

        -- =====================================================
        -- FASE 0: Reset y verificacion inicial
        -- =====================================================

        report "======================================================" severity note;
        report " NeuroVHDL -- TB CNN MNIST v2 (Rama Modularity)" severity note;
        report " FPGA target: Cyclone IV EP4CE22" severity note;
        report " Arquitectura: Conv3x3+ReLU -> MaxPool -> FC64 -> FC10" severity note;
        report "======================================================" severity note;
        report " Imagenes a probar : " & integer'image(N_IMAGES) severity note;
        report " Timeout por infer.: " & integer'image(TIMEOUT_CYC) & " ciclos" severity note;
        report " Periodo reloj     : " & time'image(CLK_PERIOD) severity note;
        report "------------------------------------------------------" severity note;

        reset <= '1';
        start <= '0';
        img_wr <= '0';
        wait_clk(5);
        reset <= '0';
        wait_clk(2);

        -- Verificar estado inicial = S_IDLE
        assert state_dbg = "00000001"
            report "[FAIL] Estado inicial no es S_IDLE: " &
                   slv_to_str(state_dbg)
            severity error;

        assert done = '0'
            report "[FAIL] 'done' debe estar en '0' tras reset"
            severity error;

        report "[PASS] Reset inicial: FSM en S_IDLE" severity note;

        -- Verificar que sin start la FSM no avanza
        wait_clk(10);
        assert state_dbg = "00000001"
            report "[FAIL] FSM avanza sin pulso start"
            severity error;

        report "[PASS] Sin start: FSM permanece en S_IDLE" severity note;

        -- =====================================================
        -- FASE 1: Test de reset en caliente (opcional)
        -- =====================================================

        if DO_RESET_TEST then
            report "------------------------------------------------------" severity note;
            report "[TEST] Reset en caliente durante operacion" severity note;

            -- Aplicar start sin imagen valida para entrar en ENTRADA
            start <= '1';
            wait_clk(1);
            start <= '0';
            wait_clk(3);

            -- Reset a la mitad
            reset <= '1';
            wait_clk(2);
            reset <= '0';
            wait_clk(2);

            assert state_dbg = "00000001"
                report "[FAIL] FSM no vuelve a S_IDLE tras reset en caliente"
                severity error;

            report "[PASS] Reset en caliente: FSM regresa a S_IDLE" severity note;
        end if;

        -- =====================================================
        -- FASE 2: Abrir archivos de datos
        -- =====================================================

        file_open(f_images, "test_images.txt", read_mode);
        file_open(f_labels, "test_labels.txt", read_mode);

        report "======================================================" severity note;
        report " Iniciando bucle de inferencias CNN" severity note;
        report "======================================================" severity note;

        -- =====================================================
        -- FASE 3: Bucle principal de inferencias
        -- =====================================================

        for img_i in 0 to N_IMAGES - 1 loop

            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
            -- 3a. Reset por imagen
            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

            reset <= '1';
            wait_clk(3);
            reset <= '0';
            wait_clk(2);

            assert state_dbg = "00000001"
                report "[WARN] FSM no en IDLE al iniciar imagen " &
                       integer'image(img_i)
                severity warning;

            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
            -- 3b. Carga de imagen en BRAM (784 pixeles)
            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

            img_wr <= '1';

            for px in 0 to 783 loop
                -- Leer siguiente linea del archivo
                readline(f_images, line_img);
                read(line_img, pix_slv);

                img_addr <= std_logic_vector(to_unsigned(px, 10));
                img_din  <= pix_slv;

                wait until rising_edge(clk);
            end loop;

            img_wr   <= '0';
            img_addr <= (others => '0');
            img_din  <= (others => '0');
            wait_clk(2);

            -- Verificar FSM sigue en IDLE tras carga
            assert state_dbg = "00000001"
                report "[FAIL] FSM salio de IDLE durante carga de imagen " &
                       integer'image(img_i)
                severity error;

            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
            -- 3c. Pulso start (1 ciclo)
            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

            start <= '1';
            wait until rising_edge(clk);
            start <= '0';

            -- Verificar transicion inmediata a S_ENTRADA
            wait until rising_edge(clk);
            assert state_dbg = "00000010"
                report "[WARN] FSM no entro en S_ENTRADA tras start (img " &
                       integer'image(img_i) & "): " &
                       fsm_state_name(state_dbg)
                severity warning;

            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
            -- 3d. Espera de done con timeout y conteo ciclos
            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

            timeout_cnt := 0;
            fsm_error   := false;

            wait_loop : loop
                wait until rising_edge(clk);
                timeout_cnt := timeout_cnt + 1;

                -- Deteccion de estado ERROR
                if state_dbg = "10000000" then
                    report "[FAIL] FSM entro en S_ERR en imagen " &
                           integer'image(img_i) &
                           " (ciclo " & integer'image(timeout_cnt) & ")"
                    severity error;
                    fsm_error := true;
                    exit wait_loop;
                end if;

                exit wait_loop when done = '1';

                if timeout_cnt >= TIMEOUT_CYC then
                    report "[TIMEOUT] Imagen " & integer'image(img_i) &
                           " supero " & integer'image(TIMEOUT_CYC) &
                           " ciclos -- FSM: " & fsm_state_name(state_dbg)
                    severity warning;
                    n_timeout := n_timeout + 1;
                    exit wait_loop;
                end if;
            end loop;

            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
            -- 3e. Lectura de resultado
            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

            predicted := to_integer(unsigned(class_out));

            -- Verificar que valid_out este activo junto con done
            assert valid_out = '1' or fsm_error
                report "[WARN] valid_out='0' cuando done='1' (img " &
                       integer'image(img_i) & ")"
                severity warning;

            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
            -- 3f. Lectura de etiqueta esperada
            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

            readline(f_labels, line_lbl);
            lbl_val := 0;

            read_lbl_loop : loop
                read(line_lbl, lbl_char, got_char);
                exit read_lbl_loop when not got_char;
                if lbl_char >= '0' and lbl_char <= '9' then
                    lbl_val := lbl_val * 10 +
                               (character'pos(lbl_char) - character'pos('0'));
                end if;
            end loop;

            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
            -- 3g. Comparacion y reporte por imagen
            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

            n_total := n_total + 1;

            -- Estadisticas de ciclos
            if timeout_cnt < min_cycles then min_cycles := timeout_cnt; end if;
            if timeout_cnt > max_cycles and timeout_cnt < TIMEOUT_CYC then
                max_cycles := timeout_cnt;
            end if;
            if timeout_cnt < TIMEOUT_CYC then
                sum_cycles := sum_cycles + timeout_cnt;
            end if;

            if not fsm_error and timeout_cnt < TIMEOUT_CYC then
                if predicted = lbl_val then
                    n_correct := n_correct + 1;
                    report "[OK  ] img=" & integer'image(img_i) &
                           " | pred=" & integer'image(predicted) &
                           " | real=" & integer'image(lbl_val) &
                           " | ciclos=" & integer'image(timeout_cnt)
                    severity note;
                else
                    report "[FAIL] img=" & integer'image(img_i) &
                           " | pred=" & integer'image(predicted) &
                           " | real=" & integer'image(lbl_val) &
                           " | ciclos=" & integer'image(timeout_cnt)
                    severity warning;
                end if;
            end if;

            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
            -- 3h. Verificar retorno a IDLE
            -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

            wait_clk(5);
            assert state_dbg = "00000001"
                report "[WARN] FSM no retorno a S_IDLE tras done (img " &
                       integer'image(img_i) & "): " &
                       fsm_state_name(state_dbg)
                severity warning;

        end loop; -- fin bucle imagenes

        -- =====================================================
        -- FASE 4: Cerrar archivos
        -- =====================================================

        file_close(f_images);
        file_close(f_labels);

        -- =====================================================
        -- FASE 5: Reporte estadistico final
        -- =====================================================

        report "======================================================" severity note;
        report " RESULTADO FINAL -- CNN MNIST NeuroVHDL" severity note;
        report "------------------------------------------------------" severity note;
        report " Imagenes evaluadas : " & integer'image(n_total) severity note;
        report " Clasificadas OK    : " & integer'image(n_correct) severity note;
        report " Timeouts           : " & integer'image(n_timeout) severity note;

        if n_total > 0 then
            report " Precision          : " &
                   integer'image((n_correct * 100) / n_total) & "%" severity note;
        end if;

        if n_total - n_timeout > 0 then
            report " Ciclos minimos     : " & integer'image(min_cycles) severity note;
            report " Ciclos maximos     : " & integer'image(max_cycles) severity note;
            report " Ciclos promedio    : " &
                   integer'image(sum_cycles / (n_total - n_timeout)) severity note;
            report " Latencia min (us)  : " &
                   integer'image((min_cycles * 10) / 1000) severity note;
            report " Latencia max (us)  : " &
                   integer'image((max_cycles * 10) / 1000) severity note;
        end if;

        report "======================================================" severity note;

        -- Aserciones globales de calidad
        assert n_timeout = 0
            report "[GLOBAL] " & integer'image(n_timeout) &
                   " inferencias terminaron en TIMEOUT -- revisar pipeline"
            severity error;

        assert (n_correct * 100) / n_total >= 60
            report "[GLOBAL] Precision < 60% -- verificar cuantizacion de pesos MIF"
            severity error;

        -- Fin de simulacion
        sim_done <= '1';

        assert false
            report "Simulacion completada exitosamente."
            severity failure;

        wait;
    end process;

    -- =========================================================
    -- MONITOR FSM: reporta cada transicion de estado
    -- =========================================================

    fsm_monitor : process(state_dbg)
    begin
        if state_dbg /= fsm_state_prev then
            -- Solo reportar transiciones validas (no el estado inicial X)
            if state_dbg /= "00000000" then
                report "[FSM] " & fsm_state_name(fsm_state_prev) &
                       " -> " & fsm_state_name(state_dbg)
                severity note;
            end if;
        end if;
        fsm_state_prev <= state_dbg;
    end process;

    -- =========================================================
    -- MONITOR valid_out: verifica protocolo handshake
    -- =========================================================

    valid_monitor : process(clk)
    begin
        if rising_edge(clk) then
            if valid_out = '1' then
                assert done = '1' or state_dbg = "00100000"
                    report "[WARN] valid_out='1' en estado inesperado: " &
                           fsm_state_name(state_dbg)
                    severity warning;
            end if;
        end if;
    end process;

    -- =========================================================
    -- MONITOR DONE: done solo debe durar 1 ciclo
    -- =========================================================

    done_monitor : process(clk)
        variable done_cnt : integer := 0;
    begin
        if rising_edge(clk) then
            if done = '1' then
                done_cnt := done_cnt + 1;
                assert done_cnt <= 2
                    report "[WARN] 'done' activo mas de 2 ciclos consecutivos"
                    severity warning;
            else
                done_cnt := 0;
            end if;
        end if;
    end process;

end architecture;
