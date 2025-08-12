# Stage 1: Build the Angular app
FROM node:20 AS build
WORKDIR /app
COPY . .
RUN npm install
RUN npm run build --prod

# Stage 2: Serve with nginx
FROM nginx:alpine
COPY --from=build /app/dist/book-recommender-ui /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Replace env.json with container-specific version
COPY src/assets/env.prod.json /usr/share/nginx/html/assets/env.json
