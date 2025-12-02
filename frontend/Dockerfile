# ============================
# Build Stage
# ============================
FROM node:20-alpine AS build

WORKDIR /app

# Nur die Package-Dateien zuerst kopieren, damit der Cache besser greift
COPY package*.json ./

# Falls du yarn/pnpm nutzt, hier entsprechend anpassen
RUN npm install

# Restlichen Code kopieren und bauen
COPY . .
RUN npm run build

# ============================
# Runtime Stage
# ============================
FROM nginx:1.27-alpine

# Build-Artefakte ins nginx-HTML-Verzeichnis
COPY --from=build /app/dist /usr/share/nginx/html

# (Optional) eigene nginx-Config:
# COPY ./docker/nginx/frontend.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
