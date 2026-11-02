# Imagen Docker de la app, en dos etapas ("multi-stage build"):
#   1. "build": una imagen con el JDK completo y Maven, que compila el .jar.
#   2. La imagen final: solo el JRE (lo justo para EJECUTAR Java) y el .jar.
# Así la imagen final no lleva el compilador ni el código fuente: es más pequeña y más segura.

# --- Etapa 1: compilar ---------------------------------------------------------
# --platform=$BUILDPLATFORM: esta etapa se ejecuta con el procesador del ordenador que construye
# (rápido, sin emular). Da igual que el servidor sea ARM: un .jar de Java funciona en cualquier procesador.
# @sha256: la imagen exacta, no "la que haya hoy con esa etiqueta". Dependabot propone las nuevas (.github/dependabot.yml).
FROM --platform=$BUILDPLATFORM eclipse-temurin:21-jdk@sha256:ebfbb18d11ff163ee83b21258acf12248af48d22a0fdfdc68fa1a1516c05976a AS build
WORKDIR /app

# mvnw comprueba la huella SHA-256 del .zip de Maven (maven-wrapper.properties). Sin unzip bajaría el .tar.gz,
# cuya huella es otra, y la comprobación fallaría.
RUN apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/*

# Primero solo lo necesario para descargar dependencias. Docker guarda cada paso en caché:
# si el pom.xml no cambia, la próxima vez se salta la descarga (que es lo lento).
COPY .mvn/ .mvn/
COPY mvnw pom.xml ./
RUN chmod +x mvnw && ./mvnw -q -B dependency:go-offline

# Luego el código, y compilamos (los tests ya los pasamos en local; aquí los saltamos).
COPY src/ src/
RUN ./mvnw -q -B package -DskipTests

# --- Etapa 2: la imagen que se ejecuta ------------------------------------------
FROM eclipse-temurin:21-jre@sha256:0b99b3376fbb50dbf9c0af8535fdd5b8eb0d3fdfc8b1e4967f383b6919f6901a
WORKDIR /app

# No ejecutamos como root: si alguien lograra colarse en la app, tendría menos permisos.
# UID fijo: en el servidor, la carpeta data/ es de este usuario (ver ec2-user-data.sh y deploy.sh).
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app app
USER app

COPY --from=build /app/target/rag-peat-0.0.1-SNAPSHOT.jar app.jar

EXPOSE 8080
# MaxRAMPercentage: Java usa como máximo el 75 % de la memoria del contenedor, y deja el resto
# al sistema. Sin esto, en un servidor pequeño la JVM podría pedir más memoria de la que hay.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
