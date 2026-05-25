"""
CNN MNIST - Entrenamiento y exportacion de pesos para FPGA Cyclone IV
PyTorch version

Arquitectura:
    Conv(8 filtros 3x3) -> ReLU -> MaxPool(2x2)
    -> FC(64) -> FC(10)

Cuantizacion:
    Q1.7 signed int8

EXPORTA:
    - kernel0.mif ... kernel7.mif
    - conv1_bias.mif
    - fc1_weights.mif
    - fc1_biases.mif
    - fc2_weights.mif
    - fc2_biases.mif
    - imagenes de prueba
"""

import os
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim

from torchvision import datasets, transforms
from torch.utils.data import DataLoader, random_split

# ============================================================
# HIPERPARAMETROS
# ============================================================

EPOCHS      = 10
BATCH_SIZE  = 128
LR          = 1e-3

FRAC_BITS   = 7
TOTAL_BITS  = 8

OUT_DIR     = "weights"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# ============================================================
# CUANTIZACION Q1.7
# ============================================================

def to_q17(val):
    """
    Float -> int8 Q1.7
    rango:
        -128 .. 127
    """

    scaled = val * (2 ** FRAC_BITS)

    clamped = np.clip(
        np.round(scaled),
        -128,
        127
    )

    return clamped.astype(np.int8)


def from_q17(val):
    return val.astype(np.float32) / (2 ** FRAC_BITS)

# ============================================================
# ESCRITURA MIF
# ============================================================

def write_mif(path, data_int8):

    depth = len(data_int8)

    with open(path, 'w') as f:

        f.write(f"DEPTH = {depth};\n")
        f.write("WIDTH = 8;\n")
        f.write("ADDRESS_RADIX = UNS;\n")
        f.write("DATA_RADIX = HEX;\n")
        f.write("CONTENT BEGIN\n")

        for i, v in enumerate(data_int8):

            hex_val = int(v) & 0xFF

            f.write(f"  {i} : {hex_val:02X};\n")

        f.write("END;\n")


# ============================================================
# EXPORTACION CONV1
# ============================================================

def export_conv1(conv_layer):

    print("\n[EXPORTANDO CONV1]")

    # PyTorch:
    # [out_ch, in_ch, kH, kW]
    #
    # conv1.weight.shape = [8,1,3,3]

    w = conv_layer.weight.detach().cpu().numpy()
    b = conv_layer.bias.detach().cpu().numpy()

    w_q = to_q17(w)
    b_q = to_q17(b)

    print(f"  weights shape = {w_q.shape}")
    print(f"  bias shape    = {b_q.shape}")

    # ========================================================
    # EXPORTAR 8 KERNELS INDIVIDUALES
    # ========================================================

    for filt in range(8):

        # [1,3,3]
        kernel = w_q[filt, 0]

        # flatten:
        # 0 1 2
        # 3 4 5
        # 6 7 8

        kernel_flat = kernel.flatten()

        path = f"{OUT_DIR}/kernel{filt}.mif"

        write_mif(path, kernel_flat)

        print(f"  kernel{filt}.mif generado")

    # ========================================================
    # EXPORTAR BIAS
    # ========================================================

    write_mif(
        f"{OUT_DIR}/conv1_bias.mif",
        b_q.flatten()
    )

    print("  conv1_bias.mif generado")

    # ========================================================
    # ERROR CUANTIZACION
    # ========================================================

    err_w = np.max(np.abs(w - from_q17(w_q)))
    err_b = np.max(np.abs(b - from_q17(b_q)))

    print(f"  err_max_weights = {err_w:.6f}")
    print(f"  err_max_bias    = {err_b:.6f}")


# ============================================================
# EXPORTACION FC
# ============================================================

def export_fc(name, layer):

    print(f"\n[EXPORTANDO {name}]")

    w = layer.weight.detach().cpu().numpy()
    b = layer.bias.detach().cpu().numpy()

    # PyTorch:
    # Linear:
    # [out_features, in_features]

    w_q = to_q17(w)
    b_q = to_q17(b)

    print(f"  weights shape = {w_q.shape}")
    print(f"  bias shape    = {b_q.shape}")

    # flatten row-major
    write_mif(
        f"{OUT_DIR}/{name}_weights.mif",
        w_q.flatten()
    )

    write_mif(
        f"{OUT_DIR}/{name}_biases.mif",
        b_q.flatten()
    )

    err_w = np.max(np.abs(w - from_q17(w_q)))
    err_b = np.max(np.abs(b - from_q17(b_q)))

    print(f"  err_max_weights = {err_w:.6f}")
    print(f"  err_max_bias    = {err_b:.6f}")


# ============================================================
# MODELO CNN
# ============================================================

class MNIST_CNN(nn.Module):

    def __init__(self):

        super().__init__()

        # 28x28 -> 26x26
        self.conv1 = nn.Conv2d(
            in_channels=1,
            out_channels=8,
            kernel_size=3,
            padding=0,
            bias=True
        )

        self.relu1 = nn.ReLU()

        # 26x26 -> 13x13
        self.pool1 = nn.MaxPool2d(2)

        # 13*13*8 = 1352
        self.fc1 = nn.Linear(1352, 64)

        self.relu2 = nn.ReLU()

        self.fc2 = nn.Linear(64, 10)

    def forward(self, x):

        x = self.conv1(x)
        x = self.relu1(x)

        x = self.pool1(x)

        x = torch.flatten(x, 1)

        x = self.fc1(x)
        x = self.relu2(x)

        x = self.fc2(x)

        return x


# ============================================================
# DATASET
# ============================================================

transform = transforms.Compose([
    transforms.ToTensor()
])

train_dataset = datasets.MNIST(
    root="./data",
    train=True,
    download=True,
    transform=transform
)

test_dataset = datasets.MNIST(
    root="./data",
    train=False,
    download=True,
    transform=transform
)

# ============================================================
# TRAIN / VALID SPLIT
# ============================================================

train_size = int(0.9 * len(train_dataset))
val_size   = len(train_dataset) - train_size

train_dataset, val_dataset = random_split(
    train_dataset,
    [train_size, val_size]
)

train_loader = DataLoader(
    train_dataset,
    batch_size=BATCH_SIZE,
    shuffle=True
)

val_loader = DataLoader(
    val_dataset,
    batch_size=BATCH_SIZE,
    shuffle=False
)

test_loader = DataLoader(
    test_dataset,
    batch_size=BATCH_SIZE,
    shuffle=False
)

# ============================================================
# MODELO
# ============================================================

model = MNIST_CNN().to(DEVICE)

print(model)

# ============================================================
# LOSS / OPTIMIZER
# ============================================================

criterion = nn.CrossEntropyLoss()

optimizer = optim.Adam(
    model.parameters(),
    lr=LR
)

# ============================================================
# ENTRENAMIENTO
# ============================================================

print("\n[ENTRENAMIENTO]")

for epoch in range(EPOCHS):

    model.train()

    running_loss = 0.0
    correct = 0
    total = 0

    for images, labels in train_loader:

        images = images.to(DEVICE)
        labels = labels.to(DEVICE)

        optimizer.zero_grad()

        outputs = model(images)

        loss = criterion(outputs, labels)

        loss.backward()

        optimizer.step()

        running_loss += loss.item()

        _, predicted = torch.max(outputs, 1)

        total += labels.size(0)
        correct += (predicted == labels).sum().item()

    train_acc = 100.0 * correct / total

    # ========================================================
    # VALIDACION
    # ========================================================

    model.eval()

    val_correct = 0
    val_total = 0

    with torch.no_grad():

        for images, labels in val_loader:

            images = images.to(DEVICE)
            labels = labels.to(DEVICE)

            outputs = model(images)

            _, predicted = torch.max(outputs, 1)

            val_total += labels.size(0)

            val_correct += (predicted == labels).sum().item()

    val_acc = 100.0 * val_correct / val_total

    print(
        f"Epoch [{epoch+1}/{EPOCHS}] "
        f"Loss={running_loss:.4f} "
        f"TrainAcc={train_acc:.2f}% "
        f"ValAcc={val_acc:.2f}%"
    )

# ============================================================
# TEST
# ============================================================

model.eval()

test_correct = 0
test_total = 0

with torch.no_grad():

    for images, labels in test_loader:

        images = images.to(DEVICE)
        labels = labels.to(DEVICE)

        outputs = model(images)

        _, predicted = torch.max(outputs, 1)

        test_total += labels.size(0)

        test_correct += (predicted == labels).sum().item()

test_acc = 100.0 * test_correct / test_total

print(f"\n[RESULTADO] Test accuracy = {test_acc:.2f}%")

# ============================================================
# EXPORTACION
# ============================================================

os.makedirs(OUT_DIR, exist_ok=True)

export_conv1(model.conv1)

export_fc("fc1", model.fc1)

export_fc("fc2", model.fc2)

# ============================================================
# EXPORTAR IMAGENES TEST
# ============================================================

print("\n[EXPORTANDO TEST IMAGES]")

N_TEST = 100

test_imgs = []
test_labels = []

for i in range(N_TEST):

    img, lbl = test_dataset[i]

    img_u8 = (img.numpy()[0] * 255).astype(np.uint8)

    test_imgs.append(img_u8)

    test_labels.append(lbl)

test_imgs = np.array(test_imgs)
test_labels = np.array(test_labels, dtype=np.uint8)

# RAW BIN
test_imgs.tofile(f"{OUT_DIR}/test_images.bin")
test_labels.tofile(f"{OUT_DIR}/test_labels.bin")

# IMAGE0 MIF
write_mif(
    f"{OUT_DIR}/image0.mif",
    test_imgs[0].flatten().astype(np.int8)
)

# TXT
with open(f"{OUT_DIR}/test_images.txt", 'w') as f:

    for img in test_imgs:

        for px in img.flatten():

            f.write(f"{px:08b}\n")

with open(f"{OUT_DIR}/test_labels.txt", 'w') as f:

    for lbl in test_labels:

        f.write(f"{lbl}\n")

print(f"  {N_TEST} imagenes exportadas")

# ============================================================
# RESUMEN
# ============================================================

print(f"\n[ARCHIVOS GENERADOS EN '{OUT_DIR}/']")

for fn in sorted(os.listdir(OUT_DIR)):

    sz = os.path.getsize(f"{OUT_DIR}/{fn}")

    print(f"  {fn:35s} {sz:8d} bytes")

print("\n[LISTO]")
print("Copiar .mif a Quartus")
print("Usar kernel0.mif ... kernel7.mif en las ROMs")