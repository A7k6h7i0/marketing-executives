import axios from "axios";

function exotelClient() {
  const sid = process.env.EXOTEL_SID;
  const apiKey = process.env.EXOTEL_API_KEY;
  const apiToken = process.env.EXOTEL_API_TOKEN;
  if (!sid || !apiKey || !apiToken) return null;

  return axios.create({
    baseURL: `https://${apiKey}:${apiToken}@api.exotel.com/v1/Accounts/${sid}`,
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    timeout: 10_000,
  });
}

export async function connectCall({
  from,
  to,
  callerId,
  statusCallback,
}: {
  from: string;
  to: string;
  callerId?: string;
  statusCallback?: string;
}) {
  const client = exotelClient();
  if (!client) throw new Error("Exotel is not configured");

  const params = new URLSearchParams();
  params.append("From", from);
  params.append("To", to);
  params.append("CallerId", callerId || process.env.EXOTEL_VIRTUAL_NUMBER || "");
  if (statusCallback) params.append("StatusCallback", statusCallback);
  params.append("Record", "true");

  const { data } = await client.post("/Calls/connect.json", params);
  if (data?.RestException) {
    const message =
      data.RestException.Message || data.RestException.message || "Exotel rejected the call request";
    throw new Error(message);
  }

  const call = data.Call || data;
  const sid = call.Sid || call.sid;
  if (!sid) throw new Error("Exotel did not return a call SID");
  return call;
}
