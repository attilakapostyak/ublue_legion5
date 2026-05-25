podman build -t development .

echo "Development container ready."
echo "Create container: toolbox create --image development development"
echo "Enter container: toolbox enter development"

podman stop development
podman ps

toolbox rm development
toolbox create --image development development

