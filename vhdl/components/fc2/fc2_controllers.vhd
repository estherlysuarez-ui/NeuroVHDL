-- ============================================================
-- Modulo: fc2_controller.vhd
-- Descripcion: FSM de control para la capa de clasificacion FC2.
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fc2_controllers is
    port (
        clk             : in  std_logic;
        reset           : in  std_logic;
        en              : in  std_logic;
        valid_in        : in  std_logic;
        
        -- Entradas desde contadores
        cnt_in_done     : in  std_logic;
        cnt_weight_done : in  std_logic;
        cnt_neur_done   : in  std_logic;
        
        -- Control de contadores
        cnt_in_en       : out std_logic;
        cnt_in_clr      : out std_logic;
        cnt_weight_en   : out std_logic;
        cnt_weight_clr  : out std_logic;
        cnt_neur_en     : out std_logic;
        cnt_neur_clr    : out std_logic;
        
        -- Modos e interfaces
        act_wr          : out std_logic;
        act_addr_sel    : out std_logic; -- '0': load, '1': calc
        mac_en          : out std_logic;
        mac_clr         : out std_logic;
        
        -- Control de Argmax y Salida
        argmax_update   : out std_logic;
        argmax_reset    : out std_logic;
        out_valid       : out std_logic;
        layer_done      : out std_logic
    );
end entity;

architecture rtl of fc2_controllers is
    type t_state is (S_LOAD, S_CALC, S_FLUSH, S_BIAS, S_ARGMAX, S_OUT, S_DONE);
    signal state     : t_state := S_LOAD;
    signal flush_cnt : unsigned(1 downto 0) := (others => '0');
begin

    process(clk) begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= S_LOAD;
                flush_cnt <= (others => '0');
            else
                case state is
                    when S_LOAD =>
                        if en = '1' and valid_in = '1' then
                            if cnt_in_done = '1' then state <= S_CALC; end if;
                        end if;
                    when S_CALC =>
                        if cnt_weight_done = '1' then
                            flush_cnt <= (others => '0');
                            state <= S_FLUSH;
                        end if;
                    when S_FLUSH =>
                        flush_cnt <= flush_cnt + 1;
                        if flush_cnt = 2 then state <= S_BIAS; end if;
                    when S_BIAS =>
                        state <= S_ARGMAX;
                    when S_ARGMAX =>
                        if cnt_neur_done = '1' then state <= S_OUT;
                        else state <= S_CALC; end if;
                    when S_OUT =>  state <= S_DONE;
                    when S_DONE => if en = '0' then state <= S_LOAD; end if;
                    when others => state <= S_LOAD;
                end case;
            end if;
        end if;
    end process;

    -- Logica de salidas de control (Combinacional dependiente del Estado)
    cnt_in_en      <= '1' when state = S_LOAD and en = '1' and valid_in = '1' else '0';
    cnt_in_clr     <= '1' when state = S_LOAD and en = '1' and valid_in = '1' and cnt_in_done = '1' else '0';
    
    act_wr         <= '1' when state = S_LOAD and en = '1' and valid_in = '1' else '0';
    act_addr_sel   <= '0' when state = S_LOAD else '1';
    
    mac_en         <= '1' when state = S_CALC else '0';
    mac_clr        <= '1' when state = S_ARGMAX or (state = S_LOAD and en = '1' and valid_in = '1' and cnt_in_done = '1') else '0';
    
    cnt_weight_en  <= '1' when state = S_CALC else '0';
    cnt_weight_clr <= '1' when state = S_CALC and cnt_weight_done = '1' else '0';
    
    cnt_neur_en    <= '1' when state = S_ARGMAX and cnt_neur_done = '0' else '0';
    cnt_neur_clr   <= '1' when state = S_ARGMAX and cnt_neur_done = '1' else '0';
    
    argmax_reset   <= '1' when state = S_LOAD and en = '1' and valid_in = '1' and cnt_in_done = '1' else '0';
    argmax_update  <= '1' when state = S_ARGMAX else '0';
    
    out_valid      <= '1' when state = S_OUT else '0';
    layer_done     <= '1' when state = S_OUT or state = S_DONE else '0';

end architecture;