import pandas as pd
from sklearn.tree import DecisionTreeClassifier, plot_tree
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
from sklearn.preprocessing import LabelEncoder
import matplotlib.pyplot as plt
import json

# Step 1: Membaca Dataset dari File Excel
file_path = r"C:\Users\Lenovo\Documents\codes\NYOBAIN LAGI\All v2.xlsx"  # Path file Excel
df = pd.read_excel(file_path)

# Normalisasi nama kolom
df.columns = df.columns.str.strip()

# Step 2: Encoding Categorical Variables
encoders = {}
for col in ["Recurring", "Price", "Taste", "Favorite"]:
    le = LabelEncoder()
    df[col] = le.fit_transform(df[col])
    encoders[col] = le  # Simpan encoder-nya

for col, le in encoders.items():
    print(f"Mapping untuk kolom '{col}':")
    for i, label in enumerate(le.classes_):
        print(f"  {i} -> {label}")
    print()

# Step 3: Splitting Features and Target
X = df[["Recurring", "Price", "Taste"]]
y = df["Favorite"]

# Pisahkan menjadi data latih dan data uji
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

# Step 4: Building the Decision Tree Model
model = DecisionTreeClassifier(criterion="entropy", random_state=0)
model.fit(X, y)

# Step 5: Visualizing the Decision Tree
plt.figure(figsize=(15, 10))
plot_tree(
    model,
    feature_names=["Recurring", "Price", "Taste"],
     class_names=encoders["Favorite"].inverse_transform(model.classes_),
    filled=True,
    rounded=True
)
plt.title("Decision Tree for Favorite Prediction", fontsize=16)
output_image_path = r"C:\Users\Lenovo\Documents\codes\NYOBAIN LAGI\decision_tree_visual.png"
plt.savefig(output_image_path, dpi=300, bbox_inches="tight")  # Simpan sebagai PNG dengan resolusi tinggi

plt.show()



# Step 10: Menampilkan Akurasi
y_pred = model.predict(X_test)
accuracy = accuracy_score(y_test, y_pred)
print(f"Akurasi model Decision Tree: {accuracy * 100:.2f}%")

# Step 11: Export Model as JSON
def tree_to_dict(tree, feature_names):
    """
    Mengubah struktur decision tree menjadi dictionary.
    """
    tree_ = tree.tree_
    feature_name = [
        feature_names[i] if i != -2 else "Leaf"
        for i in tree_.feature
    ]

    def recurse(node):
        if tree_.feature[node] != -2:  # Bukan leaf
            return {
                "name": feature_name[node],
                "threshold": tree_.threshold[node],
                "left": recurse(tree_.children_left[node]),
                "right": recurse(tree_.children_right[node]),
            }
        else:  # Leaf
            return {
                "name": "Leaf",
                "value": tree_.value[node].tolist(),
            }

    return recurse(0)

# Konversi decision tree ke dictionary
tree_dict = tree_to_dict(model, ["Recurring", "Price", "Taste"])

# Simpan sebagai file JSON
output_path = r"C:\Users\Lenovo\Documents\codes\NYOBAIN LAGI\decision_tree_structure.json"
with open(output_path, "w") as f:
    json.dump(tree_dict, f, indent=4)

print(f"Model berhasil diekspor ke {output_path}")
