import numpy as np

# === User input ===
filename = "distance.out"  # change to your filename

# === Read the file ===
# Skip lines starting with '#' (header)
data = np.loadtxt(filename, comments='#')

# Extract columns 2 and 3 (Python uses 0-based indexing)
d1 = data[:, 1]
d2 = data[:, 2]

# === Compute statistics ===
# Mean
mean_d1 = np.mean(d1)
mean_d2 = np.mean(d2)

# Standard deviation (sample standard deviation, ddof=1)
std_d1 = np.std(d1, ddof=1)
std_d2 = np.std(d2, ddof=1)

# Standard error = standard deviation / sqrt(N)
stderr_d1 = std_d1 / np.sqrt(len(d1))
stderr_d2 = std_d2 / np.sqrt(len(d2))

# === Print results ===
print("Results:")
print(f"d1 mean = {mean_d1:.5f}, std = {std_d1:.5f}, stderr = {stderr_d1:.5f}")
print(f"d2 mean = {mean_d2:.5f}, std = {std_d2:.5f}, stderr = {stderr_d2:.5f}")
