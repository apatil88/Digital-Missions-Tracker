// D-FR01-6: the part of the Deno runtime API the Edge Functions use, so tsc can check them without
// a Deno install. Add to this file when a function starts using another Deno API.
declare const Deno: {
  env: { get(name: string): string | undefined }
  serve(handler: (req: Request) => Response | Promise<Response>): unknown
}
