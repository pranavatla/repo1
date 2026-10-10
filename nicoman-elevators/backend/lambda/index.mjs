// Enquiry endpoint: validates a form submission and emails it to the business via Amazon SES.
// Runtime: Node.js 18+ (AWS SDK v3 is included in the Lambda runtime, so no bundling is needed).
// Env vars: NOTIFY_TO (comma-separated recipients), SES_FROM (verified sender), ALLOW_ORIGIN (e.g. https://nico.atla.in)

import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";

const ses = new SESClient({});
const ALLOW_ORIGIN = process.env.ALLOW_ORIGIN || "https://nico.atla.in";
const NOTIFY_TO = (process.env.NOTIFY_TO || "").split(",").map((s) => s.trim()).filter(Boolean);
const SES_FROM = process.env.SES_FROM;

const cors = {
  "Access-Control-Allow-Origin": ALLOW_ORIGIN,
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
};
const reply = (statusCode, body) => ({
  statusCode,
  headers: { ...cors, "Content-Type": "application/json" },
  body: body === undefined ? "" : JSON.stringify(body),
});

const clean = (v, max = 300) => String(v ?? "").trim().slice(0, max);
const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const PHONE_RE = /^(\+?91)?[6-9]\d{9}$/;

export const handler = async (event) => {
  if (event.requestContext?.http?.method === "OPTIONS") return reply(204);

  let data;
  try {
    data = JSON.parse(event.body || "{}");
  } catch {
    return reply(400, { error: "Invalid request" });
  }

  // Honeypot: real visitors leave this blank. Return success so bots do not retry.
  if (data.website) return reply(200, { ok: true });

  const name = clean(data.name, 80);
  const phone = clean(data.phone, 15).replace(/[\s-]/g, "");
  if (!name || !PHONE_RE.test(phone)) {
    return reply(400, { error: "Name and a valid mobile number are required" });
  }

  const fields = [
    ["Enquiry type", clean(data.form, 60)],
    ["Name", name],
    ["Phone", phone],
    ["Location", clean(data.location, 120)],
    ["Building type", clean(data.building, 80)],
    ["Service required", clean(data.service, 60)],
    ["Details", clean(data.message, 1000)],
    ["Page", clean(data.page, 120)],
  ];

  await ses.send(
    new SendEmailCommand({
      Source: SES_FROM,
      Destination: { ToAddresses: NOTIFY_TO },
      Message: {
        Subject: { Data: `New ${clean(data.form, 60) || "website"} enquiry: ${name}` },
        Body: {
          Text: { Data: fields.map(([k, v]) => `${k}: ${v || "-"}`).join("\n") },
          Html: {
            Data: `<table cellpadding="6">${fields
              .map(([k, v]) => `<tr><td><b>${esc(k)}</b></td><td>${esc(v || "-")}</td></tr>`)
              .join("")}</table>`,
          },
        },
      },
    })
  );

  return reply(200, { ok: true });
};
