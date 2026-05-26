-- ============================================================
-- Testbench: entrada_tb.vhd
-- Descripcion: Banco de pruebas completo y auto-verificado
--              para el modulo entrada de la CNN.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_entrada is
end entity;

architecture sim of tb_entrada is

    -- Componente bajo prueba (UUT)
    component entrada
        port (
            clk       : in std_logic;
            reset     : in std_logic;
            en        : in std_logic;
            img_wr    : in std_logic;
            img_addr  : in std_logic_vector(9 downto 0);
            img_din   : in std_logic_vector(7 downto 0);
            pixel_out : out signed(7 downto 0);
            valid_out : out std_logic;
            done      : out std_logic
        );
    end component;

    -- Señales de estímulo
    signal clk        : std_logic := '0';
    signal reset      : std_logic := '0';
    signal en         : std_logic := '0';
    signal img_wr     : std_logic := '0';
    signal img_addr   : std_logic_vector(9 downto 0) := (others => '0');
    signal img_din    : std_logic_vector(7 downto 0) := (others => '0');

    -- Señales de monitoreo
    signal pixel_out  : signed(7 downto 0);
    signal valid_out  : std_logic;
    signal done       : std_logic;

    -- Periodo de reloj (50 MHz típico para Cyclone IV)
    constant CLK_PERIOD : time := 20 ns;
    
    -- Control de fin de simulación
    signal sim_terminada : boolean := false;

begin

    -- Instanciación de la Unidad Bajo Prueba (UUT)
    UUT: entrada
        port map (
            clk       => clk,
            reset     => reset,
            en        => en,
            img_wr    => img_wr,
            img_addr  => img_addr,
            img_din   => img_din,
            pixel_out => pixel_out,
            valid_out => valid_out,
            done      => done
        );

    -- Proceso de generación de reloj
    clk_process : process
    begin
        while not sim_terminada loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Proceso principal de estímulos y verificación
    stim_process : process
        variable dato_esperado : integer;
    begin
        --------------------------------------------------------
        -- FASE 1: Inicialización y Reset
        --------------------------------------------------------
        report "Fase 1: Aplicando Reset Global...";
        reset <= '1';
        en    <= '0';
        img_wr <= '0';
        wait for CLK_PERIOD * 3;
        reset <= '0';
        wait for CLK_PERIOD;

        -- Verificaciones post-reset
        assert (valid_out = '0') report "Error: valid_out no es '0' tras el reset" severity error;
        assert (done = '0')      report "Error: done no es '0' tras el reset" severity error;

        --------------------------------------------------------
        -- FASE 2: Carga Externa de la Imagen (Escritura en RAM)
        --------------------------------------------------------
        report "Fase 2: Cargando 784 pixeles de forma externa...";
        for i in 0 to 783 loop
            img_wr   <= '1';
            img_addr <= std_logic_vector(to_unsigned(i, 10));
            -- Escribimos un patrón predecible: (i mod 128) para no desbordar signed(7 downto 0)
            img_din  <= std_logic_vector(to_unsigned(i mod 128, 8));
            wait for CLK_PERIOD;
        end loop;
        
        -- Desactivar escritura externa
        img_wr   <= '0';
        img_addr <= (others => '0');
        img_din  <= (others => '0');
        wait for CLK_PERIOD * 2;

        --------------------------------------------------------
        -- FASE 3: Lectura Secuencial Automática (Stream CNN)
        --------------------------------------------------------
        report "Fase 3: Habilitando lectura secuencial (CNN Stream)...";
        en <= '1';
        
        -- Debido a la arquitectura estructural, hay una latencia total de 2 ciclos de reloj.
        -- Ciclo 1: El contador cambia, el registro 'U_REG_ADDR' captura el valor anterior.
        -- Ciclo 2: La RAM recibe la dirección registrada y procesa la lectura.
        -- Ciclo 3: El dato aparece en pixel_out.
        wait for CLK_PERIOD * 2;

        for i in 0 to 783 loop
            -- El dato esperado guardado en la RAM fue: i mod 128
            dato_esperado := i mod 128;
            
            -- Verificar señales en cada flanco de lectura efectiva
            assert (valid_out = '1') 
                report "Error: valid_out debio ser '1' en el indice " & integer'image(i) 
                severity error;
                
            assert (to_integer(pixel_out) = dato_esperado)
                report "Error en Pixel " & integer'image(i) & 
                       " | Obtenido: " & integer'image(to_integer(pixel_out)) & 
                       " | Esperado: " & integer'image(dato_esperado)
                severity error;

            -- El flag done debe activarse exactamente en el último ciclo de habilitación (i = 783)
            if i = 783 then
                assert (done = '1') 
                    report "Error: la bandera DONE no se activo en el pixel 783" 
                    severity error;
            else
                assert (done = '0') 
                    report "Error: la bandera DONE se activo antes de tiempo en el pixel " & integer'image(i)
                    severity error;
            end if;

            wait for CLK_PERIOD;
        end loop;

        --------------------------------------------------------
        -- FASE 4: Fin de Lectura y Comportamiento Posterior
        --------------------------------------------------------
        report "Fase 4: Deshabilitando modulo y verificando reposo...";
        en <= '0';
        wait for CLK_PERIOD * 3;

        assert (done = '0') report "Error: done no regreso a '0' al deshabilitar" severity error;
        
        report "--- ¡SIMULACION COMPLETADA EXITOSAMENTE SIN ERRORES DETECTADOS! ---";
        sim_terminada <= true;
        wait;
    end process;

end architecture;