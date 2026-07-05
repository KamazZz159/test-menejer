// Серверная функция-прокси для Netlify. Ключ OpenRouter хранится в переменных окружения сайта,
// в браузер тестировщика/клиента он никогда не попадает.
//
// Модель тоже задаётся здесь, а не во фронтенде — так её можно сменить на платную
// (для надёжности перед демо клиентам) одной правкой переменной окружения, без редеплоя фронта.
//
// Дополнительно: перед каждым запросом проверяется, активна ли компания (оплачена или
// ещё в пробном периоде) — это защита от того, что после ручного отключения проверки
// в браузере кто-то продолжит бесплатно пользоваться сервисом.

const DEFAULT_MODEL = "google/gemma-4-31b-it:free";
const FALLBACK_MODELS = [
  "nvidia/nemotron-3-ultra-550b-a55b:free",
  "poolside/laguna-m.1:free"
];

async function isCompanyActive(companyId) {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
  if (!companyId || !supabaseUrl || !supabaseAnonKey) return true; // нет данных для проверки — не блокируем

  try {
    const res = await fetch(`${supabaseUrl}/rest/v1/rpc/is_company_active`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": supabaseAnonKey,
        "Authorization": `Bearer ${supabaseAnonKey}`
      },
      body: JSON.stringify({ cid: companyId })
    });
    if (!res.ok) return true; // Supabase недоступен технически — не роняем сервис из-за этого
    const isActive = await res.json();
    return isActive === true;
  } catch (e) {
    return true; // fail-open при сетевой ошибке проверки — не блокируем из-за временного сбоя
  }
}

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
    const { messages, company_id, max_tokens } = JSON.parse(event.body || "{}");
    const safeMaxTokens = Math.min(Math.max(parseInt(max_tokens, 10) || 400, 50), 800); // защитный потолок

    const active = await isCompanyActive(company_id);
    if (!active) {
      return { statusCode: 403, body: JSON.stringify({ error: "TRIAL_EXPIRED" }) };
    }

    const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model,
        models: [model, ...FALLBACK_MODELS],
        messages,
        max_tokens: safeMaxTokens
      })
    });

    const data = await res.json();
    return { statusCode: res.status, body: JSON.stringify(data) };
  } catch (err) {
    return { statusCode: 500, body: JSON.stringify({ error: err.message || "Внутренняя ошибка сервера" }) };
  }
};