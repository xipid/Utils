#!/bin/bash

# Vérifier si un argument est fourni
if [ -z "$1" ]; then
    echo "Usage: $0 <path_to_executable>"
    exit 1
fi

TARGET_PATH=$(realpath "$1")
TARGET_DIR=$(dirname "$TARGET_PATH")
TARGET_NAME=$(basename "$TARGET_PATH")
NEW_BINARY_NAME="_${TARGET_NAME}"
NEW_BINARY_PATH="${TARGET_DIR}/${NEW_BINARY_NAME}"

# 1. Renommer le binaire original
echo "Renommage de $TARGET_NAME en $NEW_BINARY_NAME..."
mv "$TARGET_PATH" "$NEW_BINARY_PATH"

# 2. Créer le code source du wrapper C++
WRAPPER_SOURCE="${TARGET_PATH}_wrapper.cpp"

cat <<EOF > "$WRAPPER_SOURCE"
#include <unistd.h>
#include <vector>
#include <string>

int main(int argc, char** argv) {
    std::vector<char*> args;
    
    // QEMU Configuration
    args.push_back((char*)"/usr/bin/qemu-x86_64");
    args.push_back((char*)"-cpu");
    args.push_back((char*)"max");
    
    // Chemin vers le binaire renommé
    args.push_back((char*)"$NEW_BINARY_PATH");
    
    // Transmission des arguments
    for (int i = 1; i < argc; ++i) {
        args.push_back(argv[i]);
    }
    args.push_back(nullptr);

    // Exécution
    execvp(args[0], args.data());
    
    return 1; 
}
EOF

# 3. Compiler le wrapper
echo "Compilation du wrapper..."
g++ -O3 "$WRAPPER_SOURCE" -o "$TARGET_PATH"

# 4. Nettoyage
rm "$WRAPPER_SOURCE"
chmod +x "$TARGET_PATH"

echo "Succès ! Le wrapper remplace maintenant $TARGET_NAME."
