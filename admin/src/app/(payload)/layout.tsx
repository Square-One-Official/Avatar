/* eslint-disable @typescript-eslint/no-explicit-any */
import config from "@payload-config";
import { RootLayout } from "@payloadcms/next/layouts";
import { handleServerFunctions } from "@payloadcms/next/utilities";
import type { ServerFunctionClient } from "payload";
import { importMap } from "./admin/importMap.js";
import "@payloadcms/next/css";

/**
 * Payload v3 server function. The admin UI calls this to invoke
 * server-only logic (login, document mutations, etc.). Passes through
 * to handleServerFunctions which routes by name based on the request.
 */
const serverFunction: ServerFunctionClient = async function (args) {
  "use server";
  return handleServerFunctions({
    ...args,
    config,
    importMap,
  });
};

const Layout = ({ children }: { children: React.ReactNode }) =>
  RootLayout({ children, config, importMap, serverFunction });

export default Layout;
