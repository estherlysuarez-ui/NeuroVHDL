"""
verify_quantization.py
Carga los pesos cuantizados y verifica que la precision se mantiene.
Ejecutar DESPUES de train_and_export.py
"""
import numpy as np
import os

FRAC = 7

def from_q17(arr):
    return arr.astype(np.float32) / (2**FRAC)

def load_bin(path):
    return np.fromfile(path, dtype=np.int8)

print("=" * 50)
print("VERIFICACION DE CUANTIZACION Q1.7")
print("=" * 50)

weights_dir = "weights"
layers = [
    ("conv1", (3,3,1,8), (8,)),
    ("fc1",   (1568,64), (64,)),  # <--- CORREGIDO
    ("fc2",   (64,10),   (10,)),
]

for name, w_shape, b_shape in layers:
    w_path = f"{weights_dir}/{name}_weights.bin"
    b_path = f"{weights_dir}/{name}_biases.bin"

    if not os.path.exists(w_path):
        print(f"  {name}: archivo no encontrado, ejecutar train_and_export.py primero")
        continue

    w_q = load_bin(w_path).reshape(w_shape)
    b_q = load_bin(b_path).reshape(b_shape)
    w_f = from_q17(w_q)
    b_f = from_q17(b_q)

    print(f"\n  [{name}]")
    print(f"    Pesos:  shape={w_q.shape}  min={w_q.min()}  max={w_q.max()}")
    print(f"    Sesgos: shape={b_q.shape}  min={b_q.min()}  max={b_q.max()}")
    print(f"    Rango float: [{w_f.min():.4f}, {w_f.max():.4f}]")

    # Estadisticas de saturacion
    sat_pct = np.mean(np.abs(w_q) == 127) * 100
    if sat_pct > 5:
        print(f"    ADVERTENCIA: {sat_pct:.1f}% pesos saturados!")
    else:
        print(f"    OK: {sat_pct:.2f}% saturados (< 5%)")

print("\n" + "=" * 50)
print("Archivos MIF generados:")
for fn in sorted(os.listdir(weights_dir)):
    if fn.endswith('.mif'):
        sz = os.path.getsize(f"{weights_dir}/{fn}")
        print(f"  {fn:35s} {sz:>8d} bytes")

print("\nPaso siguiente:")
print("  1. Copiar archivos .mif al proyecto Quartus")
print("  2. Copiar archivos *_pkg.vhd al proyecto")
print("  3. En conv_relu.vhd: reemplazar KERN/BIAS con valores del pkg")
print("  4. Compilar en Quartus II y sintetizar")
print("  5. Ejecutar simulacion con run_tb.do en ModelSim")
