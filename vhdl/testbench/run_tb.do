# ==============================================================
# Script ModelSim: run_tb.do (Rutas Absolutas - Corregido)
# Proyecto:  NeuroVHDL — CNN MNIST en FPGA Cyclone IV
# Rama:      Modularity
# ==============================================================

# --- Configuracion ----------------------------------------
set TB_TOP    tb_main_v2
set WORK_LIB   work
set SIM_TIME   "5000 us"
set WAVE_FILE  "wave_cnn.do"

# --- Definicion de la Raiz del Proyecto (Ruta Absoluta) ---
set PROJ_ROOT  "/home/hssr/Downloads/Codigos/NeuroVHDL"
set MIF_DIR    "$PROJ_ROOT/weights"

# --- Limpieza y creacion de libreria ----------------------
if {[file exists $WORK_LIB]} {
    vdel -lib $WORK_LIB -all
}
vlib $WORK_LIB
vmap $WORK_LIB $WORK_LIB

# --- Compilacion: componentes base ------------------------
echo ">>> Compilando componentes base..."

vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/registro.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/contador.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/mult_add.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/comparador.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/comparadorv2.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/ram_sp.vhd

# --- Compilacion: sub-componentes conv_relu ---------------
echo ">>> Compilando sub-componentes conv_relu..."

vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/conv_relu/conv_params.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/conv_relu/line_buffer_3x3.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/conv_relu/mac_accum_array.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/conv_relu/relu_block.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/conv_relu/conv_controller.vhd

# --- Compilacion: sub-componentes maxpool -----------------
echo ">>> Compilando sub-componentes maxpool..."

vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/maxpool/max_tree.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/maxpool/maxpool_controller.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/maxpool/maxpool_counters.vhd

# --- Compilacion: sub-componentes FC1 ---------------------
echo ">>> Compilando sub-componentes FC1..."

vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/fc/fc_counters.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/fc/fc_memories.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/fc/fc_controller.vhd

# --- Compilacion: sub-componentes FC2 ---------------------
echo ">>> Compilando sub-componentes FC2..."

vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/fc2/fc2_counters.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/fc2/fc2_memories.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/fc2/fc2_datapath.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/components/fc2/fc2_controllers.vhd

# --- Compilacion: modulos CNN top-level -------------------
echo ">>> Compilando modulos CNN..."

vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/modules/fsm_control.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/modules/entrada.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/modules/conv_relu.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/modules/maxpool.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/modules/capa_oculta.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/modules/salida_clasificacion.vhd
vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/modules/main.vhd

# --- Compilacion: testbench -------------------------------
echo ">>> Compilando testbench v2..."

vcom -93 -work $WORK_LIB $PROJ_ROOT/vhdl/testbench/tb_main_v2.vhd

# --- Lanzar simulacion ------------------------------------
echo ">>> El diseño cargó correctamente. Iniciando vsim..."

vsim -t 1ns -lib $WORK_LIB ${TB_TOP}

# --- Configurar ventana de ondas --------------------------
echo ">>> Configurando ventana de ondas..."

add wave -divider "=== CNN MNIST TOP-LEVEL ==="
add wave -color yellow    -label "clk"       /tb_main_v2/clk
add wave -color orange    -label "reset"     /tb_main_v2/reset
add wave -color cyan      -label "start"     /tb_main_v2/start

add wave -divider "=== Carga Imagen ==="
add wave -color white     -label "img_wr"    /tb_main_v2/img_wr
add wave -color white     -label "img_addr"  /tb_main_v2/img_addr
add wave -radix unsigned  -color white \
                          -label "img_din"   /tb_main_v2/img_din

add wave -divider "=== FSM Control ==="
# Se escapan los corchetes con \ para que Tcl no los confunda con comandos
add wave -color magenta   -label "state_dbg\[7:0\]" /tb_main_v2/state_dbg

add wave -divider "=== Resultado Clasificacion ==="
add wave -color green     -label "done"      /tb_main_v2/done
add wave -color green     -label "valid_out" /tb_main_v2/valid_out
add wave -radix unsigned  -color green \
                          -label "class_out" /tb_main_v2/class_out

# Senales internas DUT
add wave -divider "=== CNN INTERNA ==="

add wave -divider "=== Pipeline ENTRADA ==="
add wave -label "pixel_out"   /tb_main_v2/DUT/pixel_out
add wave -label "pixel_valid" /tb_main_v2/DUT/pixel_valid

add wave -divider "=== Pipeline CONV+RELU ==="
add wave -label "conv_out"    /tb_main_v2/DUT/conv_out
add wave -label "conv_fidx"   /tb_main_v2/DUT/conv_fidx
add wave -label "conv_valid"  /tb_main_v2/DUT/conv_valid

add wave -divider "=== Pipeline MAXPOOL ==="
add wave -label "pool_out"    /tb_main_v2/DUT/pool_out
add wave -label "pool_fidx"   /tb_main_v2/DUT/pool_fidx
add wave -label "pool_valid"  /tb_main_v2/DUT/pool_valid

add wave -divider "=== Pipeline FC1 ==="
add wave -label "fc1_out"     /tb_main_v2/DUT/fc1_out
add wave -label "fc1_valid"   /tb_main_v2/DUT/fc1_valid

add wave -divider "=== Enables FSM ==="
add wave -label "en_entrada"  /tb_main_v2/DUT/en_entrada
add wave -label "en_conv"     /tb_main_v2/DUT/en_conv
add wave -label "en_pool"     /tb_main_v2/DUT/en_pool
add wave -label "en_fc"       /tb_main_v2/DUT/en_fc
add wave -label "en_out"      /tb_main_v2/DUT/en_out

add wave -divider "=== Done Bloques ==="
add wave -label "done_entrada" /tb_main_v2/DUT/done_entrada
add wave -label "done_conv"    /tb_main_v2/DUT/done_conv
add wave -label "done_pool"    /tb_main_v2/DUT/done_pool
add wave -label "done_fc"      /tb_main_v2/DUT/done_fc
add wave -label "done_out"     /tb_main_v2/DUT/done_out

# Formato de visualizacion
configure wave -namecolwidth 200
configure wave -valuecolwidth 100
configure wave -signalnamewidth 1
configure wave -timelineunits us

# Correr simulacion
echo ">>> Ejecutando tiempo de simulacion ($SIM_TIME)..."
run $SIM_TIME

echo ">>> Simulacion completada con exito."
