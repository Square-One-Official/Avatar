import { redirect } from "next/navigation";

/**
 * Root → admin redirect. The marketing site lives at aaavatar.nl;
 * admin.aaavatar.nl exists only to host Payload, so the bare host
 * jumps straight into the dashboard.
 */
export default function HomePage() {
  redirect("/admin");
}
