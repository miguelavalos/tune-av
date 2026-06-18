import { getRequest } from "@tanstack/react-start/server";

export function getRequestSearch() {
  return new URL(getRequest().url).search;
}
