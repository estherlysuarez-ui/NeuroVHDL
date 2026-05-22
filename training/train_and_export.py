"""
CNN MNIST - Entrenamiento y exportacion de pesos para FPGA Cyclone IV
Arquitectura: Conv(8 filtros 3x3) -> ReLU -> MaxPool(2x2) -> FC(64) -> FC(10)
Cuantizacion: Q1.7 (1 bit signo, 7 bits fraccion) -> rango [-1, 0.9921875]
"""

import numpy as np
import tensorflow as tf
from tensorflow import keras
import os, struct

# ─── Hiperparametros ────────────────────────────────────────────────────────
EPOCHS      = 10
BATCH_SIZE  = 128
FRAC_BITS   = 7          # bits de fraccion en Q1.7
INT_BITS    = 1          # bits de parte entera (signo incluido)
TOTAL_BITS  = 8          # 8 bits total -> signed int8
OUT_DIR     = "weights"  # carpeta de salida

# ─── Cuantizacion Q1.7 ──────────────────────────────────────────────────────
def to_q17(val):
    """Float -> Q1.7 signed 8-bit (-128..127)"""
    scaled = val * (2 ** FRAC_BITS)
    clamped = np.clip(np.round(scaled), -128, 127)
    return clamped.astype(np.int8)

def from_q17(val):
    """Q1.7 -> float (para verificacion)"""
    return val.astype(np.float32) / (2 ** FRAC_BITS)

# ─── Dataset MNIST ──────────────────────────────────────────────────────────
(x_train, y_train), (x_test, y_test) = keras.datasets.mnist.load_data()

# Normalizar a [-1, 1] para aprovechar Q1.7
x_train = x_train.astype(np.float32) / 255.0
x_test  = x_test.astype(np.float32)  / 255.0

# Agregar canal para Conv2D: (N,28,28) -> (N,28,28,1)
x_train = x_train[..., np.newaxis]
x_test  = x_test[..., np.newaxis]

y_train = keras.utils.to_categorical(y_train, 10)
y_test  = keras.utils.to_categorical(y_test,  10)

# ─── Modelo CNN ─────────────────────────────────────────────────────────────
# Disenado para minimizar recursos en FPGA:
#   - 1 capa Conv 3x3 con 8 filtros  (small)
#   - MaxPooling 2x2  -> 13x13x8 = 1352 neuronas
#   - FC oculta: 64 neuronas
#   - FC salida: 10 clases

model = keras.Sequential([
    keras.layers.Input(shape=(28, 28, 1)),

    # Bloque Convolucional + ReLU
    keras.layers.Conv2D(8, (3,3), padding='same', activation='relu',
                        use_bias=True, name='conv1'),

    # MaxPooling 2x2
    keras.layers.MaxPooling2D((2,2), name='pool1'),

    # Flatten
    keras.layers.Flatten(name='flatten'),

    # Capa Oculta FC
    keras.layers.Dense(64, activation='relu', use_bias=True, name='fc1'),

    # Capa Salida (sin activacion -> argmax en FPGA)
    keras.layers.Dense(10, activation='softmax', use_bias=True, name='fc2'),
], name='mnist_cnn')

model.summary()

# ─── Entrenamiento ───────────────────────────────────────────────────────────
model.compile(
    optimizer=keras.optimizers.Adam(1e-3),
    loss='categorical_crossentropy',
    metrics=['accuracy']
)

history = model.fit(
    x_train, y_train,
    epochs=EPOCHS,
    batch_size=BATCH_SIZE,
    validation_split=0.1,
    verbose=1
)

loss, acc = model.evaluate(x_test, y_test, verbose=0)
print(f"\n[RESULTADO] Test accuracy: {acc*100:.2f}%  |  Test loss: {loss:.4f}")

# ─── Exportacion de pesos ────────────────────────────────────────────────────
os.makedirs(OUT_DIR, exist_ok=True)

def export_layer(name, weights_float, biases_float):
    """Cuantiza y guarda pesos en .bin (raw int8) y .mif (Altera MIF)"""
    w_q = to_q17(weights_float)
    b_q = to_q17(biases_float)

    # ── Binario raw ──
    w_q.flatten().tofile(f"{OUT_DIR}/{name}_weights.bin")
    b_q.flatten().tofile(f"{OUT_DIR}/{name}_biases.bin")

    # ── MIF para inicializar BRAM en Quartus ──
    write_mif(f"{OUT_DIR}/{name}_weights.mif", w_q.flatten())
    write_mif(f"{OUT_DIR}/{name}_biases.mif",  b_q.flatten())

    # ── Cabecera VHDL con los pesos como constantes ──
    write_vhdl_pkg(name, w_q, b_q)

    err_w = np.max(np.abs(weights_float - from_q17(w_q)))
    err_b = np.max(np.abs(biases_float  - from_q17(b_q)))
    print(f"  {name}: pesos {w_q.shape}, sesgo {b_q.shape} | "
          f"err_max_w={err_w:.5f} err_max_b={err_b:.5f}")
    return w_q, b_q

def write_mif(path, data_int8):
    """Genera archivo .mif compatible con Quartus II / Altera"""
    depth = len(data_int8)
    with open(path, 'w') as f:
        f.write(f"DEPTH = {depth};\n")
        f.write(f"WIDTH = 8;\n")
        f.write(f"ADDRESS_RADIX = UNS;\n")
        f.write(f"DATA_RADIX = HEX;\n")
        f.write(f"CONTENT BEGIN\n")
        for i, v in enumerate(data_int8):
            hex_val = int(v) & 0xFF
            f.write(f"  {i} : {hex_val:02X};\n")
        f.write(f"END;\n")

def write_vhdl_pkg(name, w_q, b_q):
    """Genera package VHDL con los pesos como array de constantes"""
    flat_w = w_q.flatten()
    flat_b = b_q.flatten()
    path = f"{OUT_DIR}/{name}_pkg.vhd"
    with open(path, 'w') as f:
        f.write(f"-- Pesos cuantizados Q1.7 para capa {name}\n")
        f.write(f"-- Generado automaticamente por train_and_export.py\n")
        f.write(f"library ieee;\n")
        f.write(f"use ieee.std_logic_1164.all;\n")
        f.write(f"use ieee.numeric_std.all;\n\n")
        f.write(f"package {name}_pkg is\n\n")
        f.write(f"  -- Numero de pesos: {len(flat_w)}, sesgos: {len(flat_b)}\n")
        f.write(f"  type t_weights_{name} is array(0 to {len(flat_w)-1}) "
                f"of signed(7 downto 0);\n")
        f.write(f"  type t_biases_{name}  is array(0 to {len(flat_b)-1}) "
                f"of signed(7 downto 0);\n\n")

        # Pesos
        f.write(f"  constant C_WEIGHTS_{name.upper()} : t_weights_{name} := (\n")
        lines = [f"    {i} => to_signed({int(v)},8)" for i, v in enumerate(flat_w)]
        f.write(",\n".join(lines))
        f.write(f"\n  );\n\n")

        # Sesgos
        f.write(f"  constant C_BIASES_{name.upper()} : t_biases_{name} := (\n")
        lines = [f"    {i} => to_signed({int(v)},8)" for i, v in enumerate(flat_b)]
        f.write(",\n".join(lines))
        f.write(f"\n  );\n\n")

        f.write(f"end package {name}_pkg;\n")

print("\n[EXPORTANDO PESOS]")

# Conv1: pesos shape (3,3,1,8) -> flatten a (72,)
conv1_w, conv1_b = model.get_layer('conv1').get_weights()
print(f"  conv1 raw shapes: w={conv1_w.shape}, b={conv1_b.shape}")
export_layer('conv1', conv1_w, conv1_b)

# FC1: pesos shape (1352, 64)
fc1_w, fc1_b = model.get_layer('fc1').get_weights()
print(f"  fc1 raw shapes: w={fc1_w.shape}, b={fc1_b.shape}")
export_layer('fc1', fc1_w, fc1_b)

# FC2: pesos shape (64, 10)
fc2_w, fc2_b = model.get_layer('fc2').get_weights()
print(f"  fc2 raw shapes: w={fc2_w.shape}, b={fc2_b.shape}")
export_layer('fc2', fc2_w, fc2_b)

# ─── Exportar imagenes de prueba ─────────────────────────────────────────────
# 100 imagenes del test set -> para testbench VHDL
N_TEST = 100
test_imgs  = (x_test[:N_TEST, :, :, 0] * 255).astype(np.uint8)
test_labels = np.argmax(y_test[:N_TEST], axis=1).astype(np.uint8)

test_imgs.tofile(f"{OUT_DIR}/test_images.bin")
test_labels.tofile(f"{OUT_DIR}/test_labels.bin")

# MIF para las imagenes (las primeras 10 para simulacion rapida)
write_mif(f"{OUT_DIR}/image0.mif", test_imgs[0].flatten())

# Archivo de texto para leer en testbench
with open(f"{OUT_DIR}/test_images.txt", 'w') as f:
    for img in test_imgs:
        for px in img.flatten():
            f.write(f"{px:08b}\n")  # 1 pixel por linea en binario

with open(f"{OUT_DIR}/test_labels.txt", 'w') as f:
    for lbl in test_labels:
        f.write(f"{lbl}\n")

print(f"\n[TEST] {N_TEST} imagenes exportadas")
print(f"  Labels: {test_labels[:10]} ...")

# ─── Resumen de archivos generados ──────────────────────────────────────────
print(f"\n[ARCHIVOS GENERADOS en '{OUT_DIR}/']")
for fn in sorted(os.listdir(OUT_DIR)):
    sz = os.path.getsize(f"{OUT_DIR}/{fn}")
    print(f"  {fn:40s}  {sz:>8d} bytes")

print("\n[LISTO] Copiar archivos .mif y .vhd a proyecto Quartus")
print("        Agregar *_pkg.vhd como fuentes en Quartus II")
