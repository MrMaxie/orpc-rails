FROM node:24.18.0-bookworm-slim@sha256:6f7b03f7c2c8e2e784dcf9295400527b9b1270fd37b7e9a7285cf83b6951452d
WORKDIR /fixture
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY tsconfig.json tsconfig.compatibility.json tsconfig.rpc.json compatibility.test.ts rpc-compatibility.test.ts rpc-client.test.ts client.test.ts ./
CMD ["sleep", "infinity"]
