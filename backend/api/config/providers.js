const AI_PROVIDER_TIMEOUT_MS = 7500;
const GROQ_RECEIPT_TIMEOUT_MS = 5000;

function isAzureConfigured() {
  return Boolean(
    process.env.AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT &&
    process.env.AZURE_DOCUMENT_INTELLIGENCE_KEY
  );
}

function getAzureEndpoint() {
  return String(
    process.env.AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT || ""
  ).replace(/\/+$/, "");
}

module.exports = {
  AI_PROVIDER_TIMEOUT_MS,
  GROQ_RECEIPT_TIMEOUT_MS,
  isAzureConfigured,
  getAzureEndpoint,
};
