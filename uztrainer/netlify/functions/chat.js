// Серверная функция-прокси для Netlify. Ключ OpenRouter хранится в переменных окружения сайта,
// в браузер тестировщика/клиента он никогда не попадает.
//
// Модель тоже задаётся здесь, а не во фронтенде — так её можно сменить на платную
// (для надёжности перед демо клиентам) одной правкой переменной окружения, без редеплоя фронта.

const DEFAULT_MODEL = "google/gemma-4-31b-it:free";
const FALLBACK_MODELS = [
  "nvidia/nemotron-3-ultra-550b-a55b:free",
  "poolside/laguna-m.1:free"
];

exports.handler = async (event) => {
  if (event.httpMethod !== "POST") {
    return { statusCode: 405, body: JSON.stringify({ error: "Method not allowed" }) };
  }

  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    return { statusCode: 500, body: JSON.stringify({ error: "OPENROUTER_API_KEY не задан в настройках сайта на Netlify" }) };
  }

  const model = process.env.OPENROUTER_MODEL || DEFAULT_MODEL;

  try {
    const { messages } = JSON.parse(event.body || "{}");

    const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model,
        models: [model, ...FALLBACK_MODELS],
        messages
      })
    });

    const data = await res.json();
    return { statusCode: res.status, body: JSON.stringify(data) };
  } catch (err) {
    return { statusCode: 500, body: JSON.stringify({ error: err.message || "Внутренняя ошибка сервера" }) };
  }
};
