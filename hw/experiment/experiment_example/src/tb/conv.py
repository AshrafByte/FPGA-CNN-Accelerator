import numpy as np

window = np.array([
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
])

kernel = np.array([
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
])

result = 0

for i in range(3):
    for j in range(3):
        result += window[i][j] * kernel[i][j]

print("Window:")
print(window)

print("\nKernel:")
print(kernel)

print("\nResult =", result)

import numpy as np

kernel = np.array([
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
])

window = np.array([
    [2,  3,  4],
    [34, 35, 36],
    [66, 67, 68]
])

products = window * kernel

mac_result = np.sum(products)

# 20-bit -> 16-bit
DROP = 4
rounded = mac_result + (1 << (DROP - 1))
shifted = rounded >> DROP

# Saturation
shifted = max(-32768, min(32767, shifted))

print("Products:")
print(products)

print("MAC result =", mac_result)
print("Rounded    =", rounded)
print("Final      =", shifted)