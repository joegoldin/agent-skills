import { constants } from "node:fs";
import { access, lstat, readdir } from "node:fs/promises";
import { delimiter, join, relative, resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

async function checklists(cwd: string): Promise<string[]> {
  const pi = join(cwd, ".pi");
  const root = join(pi, "todo");
  for (const directory of [pi, root]) {
    if (!(await lstat(directory).catch((error) => {
      if (error.code !== "ENOENT") throw error;
    }))?.isDirectory()) return [];
  }
  const entries = await readdir(root, { withFileTypes: true });
  const files = await Promise.all(entries.filter((entry) => entry.isDirectory()).map(async (entry) => {
    const path = join(root, entry.name, "checklist.md");
    const stat = await lstat(path).catch((error) => {
      if (error.code !== "ENOENT") throw error;
    });
    return stat?.isFile() ? { path, modified: stat.mtimeMs } : undefined;
  }));
  return files.filter((file) => file !== undefined)
    .sort((a, b) => b.modified - a.modified || a.path.localeCompare(b.path))
    .map((file) => file.path);
}

async function findViewer(): Promise<string | undefined> {
  const configured = process.env.PI_CHECKLIST_VIEWER;
  const candidates = configured ? [configured] : (process.env.PATH ?? "").split(delimiter)
    .flatMap((dir) => dir ? [resolve(dir, "checklist-view")] : []);
  for (const path of candidates) {
    if (await access(path, constants.X_OK).then(() => true, () => false)) return path;
  }
}

export default function todos(pi: ExtensionAPI) {
  pi.registerCommand("todos", {
    description: "Open a worktree checklist in a Rex side pane",
    handler: async (_args, ctx) => {
      const { cwd, ui } = ctx;
      try {
        const files = await checklists(cwd);
        let [file] = files;
        if (!file) {
          ui.notify("No checklists in this worktree's .pi/todo directory.", "info");
          return;
        }
        if (files.length > 1) {
          const selected = await ui.select("Open checklist", files.map((path) => relative(cwd, path)));
          const match = files.find((path) => relative(cwd, path) === selected);
          if (!match) return;
          file = match;
        }

        const block = process.env.REX_BLOCK;
        const viewer = await findViewer();
        if (!block || !viewer) {
          ui.notify(viewer ? `Outside Rex. Run checklist-view with: ${file}` : `Checklist viewer unavailable. Open: ${file}`, "info");
          return;
        }
        const options = { cwd, timeout: 7000 };
        const rex = ["--autostart=false", "--timeout", "5s"];
        const identity = await pi.exec("rex", [...rex, "whoami", "--json"], options);
        if (identity.code !== 0) throw new Error(identity.stderr.trim() || "Could not contact Rex");
        const { block_id, session_id } = JSON.parse(identity.stdout);
        if (block_id !== block || typeof session_id !== "string" || !session_id.startsWith("session:")) {
          throw new Error("Could not verify the calling Rex pane");
        }
        const split = await pi.exec("rex", [
          ...rex, "split", "-s", session_id, "-b", block, "--split=right", "--ratio=40", "--focus=false",
          "-c", cwd, "--label", "Checklist", "--shell=none", "--", viewer, file,
        ], options);
        if (split.code !== 0) throw new Error(split.stderr.trim() || "Rex could not create the checklist pane");
      } catch (error) {
        ui.notify(`Could not open checklist: ${error instanceof Error ? error.message : String(error)}`, "error");
      }
    },
  });
}
