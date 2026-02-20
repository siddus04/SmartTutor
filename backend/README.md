# SmartTutor Backend (Next.js)

## Local Development

```bash
npm install
npm run dev
```

The API will be available at:

```
http://localhost:3000/api/triangles/check
```

## Deploy on Vercel

1. Set the Vercel Root Directory to `backend`.
2. Add the environment variable `OPENAI_API_KEY`.
3. Deploy.

## Required Environment Variable

- `OPENAI_API_KEY`

## Test with curl

```bash
curl -X POST http://localhost:3000/api/triangles/check \
  -H "Content-Type: application/json" \
  -d '{
    "concept": "C1",
    "task": "circle_hypotenuse",
    "right_angle_at": "C",
    "combined_png_base64": "<BASE64_PNG>"
  }'
```
