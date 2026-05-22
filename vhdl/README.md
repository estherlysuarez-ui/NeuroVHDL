# CNN MNIST en FPGA Cyclone IV — Guía Completa

## Arquitectura implementada

```
Imagen 28×28  →  Conv(8 filtros 3×3)+ReLU  →  MaxPool(2×2)  →  FC(64)+ReLU  →  FC(10)→argmax
  [784 px]         [28×28×8 = 6272]            [14×14×8=1352]    [64 neuronas]   [clase 0-9]
```

Cuantización **Q1.7** (signed 8-bit, 7 bits fracción) en todos los pesos y activaciones.

## Estructura de archivos

```
mnist_fpga/
├── python/
│   ├── train_and_export.py     ← Entrena CNN y exporta pesos
│   └── verify_quantization.py  ← Verifica cuantización
├── vhdl/
│   ├── components/             ← Bloques reutilizables
│   │   ├── contador.vhd
│   │   ├── registro.vhd
│   │   ├── mult_add.vhd        ← MAC unit (1 DSP Cyclone IV)
│   │   ├── comparador.vhd      ← Comparador + ReLU
│   │   └── ram_sp.vhd          ← RAM single-port → BRAM M9K
│   ├── modules/                ← Bloques funcionales CNN
│   │   ├── fsm_control.vhd     ← FSM ONE-HOT (7 estados)
│   │   ├── entrada.vhd         ← Lee BRAM imagen
│   │   ├── conv_relu.vhd       ← Capa convolucional + ReLU
│   │   ├── maxpool.vhd         ← MaxPooling 2×2
│   │   ├── capa_oculta.vhd     ← FC1: 1352→64
│   │   └── salida_clasificacion.vhd ← FC2: 64→10 + argmax
│   ├── top/
│   │   └── mnist_top.vhd       ← Integración top-level
│   └── testbench/
│       ├── tb_mnist_top.vhd    ← Testbench automático
│       └── run_tb.do           ← Script ModelSim
├── mnist_cnn.qsf               ← Proyecto Quartus II
└── mnist_cnn.sdc               ← Constraints timing
```

## Paso 1: Entrenamiento Python

```bash
# Instalar dependencias
pip install tensorflow numpy

# Entrenar y exportar pesos (genera carpeta weights/)
cd python
python train_and_export.py

# Verificar cuantización
python verify_quantization.py
```

Se generan en `python/weights/`:
- `conv1_weights.mif`, `conv1_biases.mif`
- `fc1_weights.mif`, `fc1_biases.mif`
- `fc2_weights.mif`, `fc2_biases.mif`
- `conv1_pkg.vhd`, `fc1_pkg.vhd`, `fc2_pkg.vhd`
- `test_images.txt`, `test_labels.txt` (para testbench)

## Paso 2: Integrar pesos en VHDL

### 2a. Pesos de conv_relu.vhd (inline)
Abrir `python/weights/conv1_pkg.vhd` y copiar los valores de
`C_WEIGHTS_CONV1` y `C_BIASES_CONV1` a las constantes `KERN` y `BIAS`
en `vhdl/modules/conv_relu.vhd`.

### 2b. Pesos FC1 y FC2 (BRAM via MIF)
En Quartus II, los archivos `fc1_weights.mif` y `fc2_weights.mif` se
asignan automáticamente a las RAMs mediante el atributo `ram_init_file`
declarado en `ram_sp.vhd`.

**Verificar** que las rutas en `ram_sp.vhd` coincidan con las del proyecto:
```vhdl
-- En capa_oculta.vhd, instancia U_W_RAM:
MIF_FILE => "fc1_weights.mif"
-- En salida_clasificacion.vhd, instancia U_W2:
MIF_FILE => "fc2_weights.mif"
```

## Paso 3: Simulación en ModelSim

```bash
# Desde la carpeta vhdl/testbench/
vsim -do run_tb.do
```

El testbench:
1. Lee `test_images.txt` (pixeles en binario, 1 por línea)
2. Simula BRAM respondiendo a `addr`
3. Lanza `start` y espera `valid_out`
4. Compara `class_out` con `test_labels.txt`
5. Reporta precisión al final

**Señales clave a monitorear:**
- `state_dbg[6:0]` — estado FSM (one-hot)
- `valid_conv`, `valid_pool`, `valid_fc1`, `valid_out`
- `class_out` — predicción final

## Paso 4: Síntesis en Quartus II

1. Abrir Quartus II → New Project → apuntar a `mnist_cnn.qsf`
2. Verificar que todos los archivos VHDL estén en la lista
3. Agregar los archivos MIF al proyecto
4. **Processing → Start Compilation**
5. Revisar reporte de síntesis:
   - LEs usados: ~3000-5000 (dentro de EP4CE22)
   - M9K BRAMs: ~6-8 bloques
   - DSP: ~1-4 elementos

## FSM One-Hot — Estados

| Bit | Estado | Acción |
|-----|--------|--------|
| 0   | S_IDLE | Espera `start=1` |
| 1   | S_CONV | Activa entrada + conv_relu |
| 2   | S_POOL | Activa maxpool |
| 3   | S_FC1  | Activa capa_oculta |
| 4   | S_OUT  | Activa salida_clasificacion |
| 5   | S_DONE | Resultado listo (1 ciclo) |
| 6   | S_ERR  | Error (estado inválido) |

## Cuantización Q1.7

| Representación | Rango | Resolución |
|---------------|-------|-----------|
| signed 8-bit  | [-1.0, +0.9921875] | 1/128 ≈ 0.0078 |

Fórmula: `valor_real = registro_int8 / 128`

Producto MAC: `16 bits → truncar bits [14:7] → Q1.7 de 8 bits`

## Recursos estimados Cyclone IV EP4CE22

| Recurso | Estimado | Disponible |
|---------|----------|-----------|
| LEs     | ~4500    | 22320     |
| M9K     | ~8       | 132       |
| DSP     | ~2       | 132       |
| Memoria | ~100 KB  | 594 KB    |

## Notas importantes

- La BRAM de imagen (784 bytes) debe cargarse ANTES de `start=1`
  (en lab: via JTAG, UART, o precargada en síntesis con otro .mif)
- Velocidad máxima estimada: 50 MHz (posiblemente hasta 80 MHz)
- Latencia de inferencia a 50 MHz: ~500K ciclos ≈ 10 ms por imagen
- El diseño es completamente síncrono (sin latches)
