-- ============================================================
-- Testbench: tb_conv.vhd
-- Descripcion: Banco de pruebas estructural para el bloque
--              Convolucion + ReLU. Genera un stream completo
--              de pixeles para validar el comportamiento.
-- ============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_conv is
end entity;

architecture sim of tb_conv is

    -- Componente bajo prueba (UUT)
    component conv_relu
        generic (
            IMG_W  : integer := 28;
            N_FILT : integer := 8;
            FRAC   : integer := 7
        );
        port (
            clk        : in std_logic;
            reset      : in std_logic;
            en         : in std_logic;
            pixel_in   : in signed(7 downto 0);
            valid_in   : in std_logic;
            image_done : in std_logic;
            conv_out   : out signed(7 downto 0);
            filt_idx   : out std_logic_vector(2 downto 0);
            valid_out  : out std_logic;
            done       : out std_logic
        );
    end component;

    -- Constantes de configuracion
    constant IMG_W_SIM  : integer := 28;
    constant CLK_PERIOD : time := 20 ns;

    -- Senales de estimulo
    signal clk        : std_logic := '0';
    signal reset      : std_logic := '0';
    signal en         : std_logic := '0';
    signal pixel_in   : signed(7 downto 0) := (others => '0');
    signal valid_in   : std_logic := '0';
    signal image_done : std_logic := '0';

    -- Senales de monitoreo
    signal conv_out   : signed(7 downto 0);
    signal filt_idx   : std_logic_vector(2 downto 0);
    signal valid_out  : std_logic;
    signal done       : std_logic;

    signal sim_terminada : boolean := false;

begin

    -- Instanciacion del modulo conv_relu
    UUT: conv_relu
        generic map (
            IMG_W  => IMG_W_SIM,
            N_FILT => 8,
            FRAC   => 7
        )
        port map (
            clk        => clk,
            reset      => reset,
            en         => en,
            pixel_in   => pixel_in,
            valid_in   => valid_in,
            image_done => image_done,
            conv_out   => conv_out,
            filt_idx   => filt_idx,
            valid_out  => valid_out,
            done       => done
        );

    -- Generador de Reloj (50 MHz)
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

    -- Proceso de verificacion en paralelo (Verifica la funcion ReLU de forma continua)
    check_process : process(clk)
    begin
        if rising_edge(clk) then
            if valid_out = '1' then
                -- Protocolo de seguridad ReLU: La salida de la funcion de activacion 
                -- bajo ninguna circunstancia puede entregar un valor negativo.
                assert (to_integer(conv_out) >= 0)
                    report "Fallo critico en ReLU: Se detecto un valor negativo (" & 
                           integer'image(to_integer(conv_out)) & ") en filt_idx: " & 
                           integer'image(to_integer(unsigned(filt_idx)))
                    severity error;
            end if;
        end if;
    end process;

    -- Proceso principal de estimulos
    stim_process : process
        variable pixel_val : integer;
    begin
        --------------------------------------------------------
        -- FASE 1: Reset Inicial
        --------------------------------------------------------
        report "Fase 1: Inicializando canales y aplicando Reset...";
        reset <= '1';
        en    <= '0';
        valid_in   <= '0';
        image_done <= '0';
        pixel_in   <= (others => '0');
        wait for CLK_PERIOD * 5;
        reset <= '0';
        wait for CLK_PERIOD * 2;

        --------------------------------------------------------
        -- FASE 2: Inyeccion del Stream de Pixeles (Imagen 28x28)
        --------------------------------------------------------
        report "Fase 2: Enviando matriz de pixeles (28x28 = 784 ciclos)...";
        en <= '1';
        
        for i in 0 to (IMG_W_SIM * IMG_W_SIM) - 1 loop
            valid_in <= '1';
            
            -- Generamos un patron oscilante entre valores positivos y negativos 
            -- para estresar y probar la logica del sumador y la ReLU externa.
            if (i mod 2) = 0 then
                pixel_val := 15;   -- Valor positivo
            else
                pixel_val := -20;  -- Valor negativo
            end if;
            
            pixel_in <= to_signed(pixel_val, 8);
            
            -- Simular bandera de finalizacion de imagen en el ultimo pixel
            if i = (IMG_W_SIM * IMG_W_SIM) - 1 then
                image_done <= '1';
            end if;
            
            wait for CLK_PERIOD;
        end loop;

        -- Apagar canales de entrada
        valid_in   <= '0';
        image_done <= '0';
        pixel_in   <= (others => '0');

        --------------------------------------------------------
        -- FASE 3: Espera del vaciado del pipeline convolucional
        --------------------------------------------------------
        report "Fase 3: Pixeles enviados. Procesando ventana interna y filtros...";
        
        -- Damos margen de ciclos de reloj para que el controlador termine 
        -- de barrer los 8 filtros (N_FILT) por cada ventana calculada.
        wait for CLK_PERIOD * 100;

        --------------------------------------------------------
        -- FASE 4: Fin de Simulacion
        --------------------------------------------------------
        report "Fase 4: Finalizando simulacion y verificando estabilidad...";
        en <= '0';
        wait for CLK_PERIOD * 5;

        report "--- TESTBENCH CONV_RELU PROCESADO CON EXITO ---";
        sim_terminada <= true;
        wait;
    end process;

end architecture;