;;; init-agent.el --- Agent Shell sidebar and context sharing -*- lexical-binding: t; -*-

(require 'subr-x)
(require 'package)

;; Packages may have been installed while this Emacs was already running.
;; Refresh package activation so this module can be loaded without a restart.
(unless (locate-library "agent-shell")
  (package-initialize))

(defgroup lcw-agent nil
  "Local Agent Shell integration."
  :group 'tools)

(defcustom lcw-agent-sidebar-width 0.36
  "Initial width of the Agent Shell side window.
The window remains manually resizable after it is created."
  :type 'number
  :group 'lcw-agent)

(defun lcw-agent-state-subdirectory (subdir)
  "Return a local state directory for Agent Shell SUBDIR.
Keep transcripts and screenshots out of the working repository."
  (let* ((cwd (or (and (fboundp 'agent-shell-cwd)
                       (ignore-errors (agent-shell-cwd)))
                  default-directory))
         (project-id (substring (secure-hash 'sha1 cwd) 0 12)))
    (expand-file-name
     (file-name-concat "state" "agent-shell" project-id subdir)
     user-emacs-directory)))

(defun lcw-agent--require ()
  "Load Agent Shell or report how to install it."
  (unless (require 'agent-shell nil t)
    (user-error
     "Agent Shell is unavailable; run M-x lcw-install-ide-packages")))

(defun lcw-agent--require-command (command)
  "Require executable COMMAND, otherwise report a useful error."
  ;; REMOTE asks `executable-find' to check the TRAMP host when the current
  ;; buffer is remote; local installation must not mask a missing remote ACP.
  (unless (executable-find command t)
    (user-error "%s is not available on this host" command)))

(defun lcw-agent-open ()
  "Choose an agent and open an Agent Shell for the current project."
  (interactive)
  (lcw-agent--require)
  ;; `agent-shell-new-shell' deliberately shows the agent picker even when
  ;; `agent-shell-preferred-agent-config' names a default agent.
  (agent-shell-new-shell))

(defun lcw-agent-start-codex ()
  "Start a new Codex conversation for the current project."
  (interactive)
  (lcw-agent--require)
  (lcw-agent--require-command "codex-acp")
  (require 'agent-shell-openai)
  (agent-shell-openai-start-codex))

(defun lcw-agent-start-pi ()
  "Start a new Pi conversation for the current project."
  (interactive)
  (lcw-agent--require)
  (lcw-agent--require-command "pi-acp")
  (require 'agent-shell-pi)
  (agent-shell-pi-start-agent))

(defun lcw-agent-send-context ()
  "Put the active region, diagnostic, or current line in the Agent prompt.
The context is inserted but not submitted, so a question can be added first."
  (interactive)
  (lcw-agent--require)
  (agent-shell-send-dwim))

(defun lcw-agent-send-region ()
  "Put the exact active region in the Agent prompt without submitting it."
  (interactive)
  (unless (use-region-p)
    (user-error "Select text first"))
  (lcw-agent--require)
  (agent-shell-send-region))

(defun lcw-agent-send-file ()
  "Put the current file in the Agent prompt without submitting it."
  (interactive)
  (lcw-agent--require)
  (agent-shell-send-file))

(defvar-keymap lcw-agent-prefix-map
  :doc "Agent Shell commands."
  "a" #'lcw-agent-open
  "c" #'lcw-agent-start-codex
  "p" #'lcw-agent-start-pi
  "s" #'lcw-agent-send-context
  "r" #'lcw-agent-send-region
  "f" #'lcw-agent-send-file
  "n" #'agent-shell-new-shell)

(keymap-global-set "C-c a" lcw-agent-prefix-map)
(keymap-set window-prefix-map "a" #'lcw-agent-open)
(keymap-set window-prefix-map "A" #'agent-shell-new-shell)

(use-package agent-shell
  :if (locate-library "agent-shell")
  :commands (agent-shell
             agent-shell-toggle
             agent-shell-new-shell
             agent-shell-send-dwim
             agent-shell-send-region
             agent-shell-send-file)
  :init
  ;; A selection wins over all implicit context.  Without a selection, a
  ;; diagnostic or the current line is more precise than sending a whole file.
  (setq agent-shell-preferred-agent-config 'codex
        agent-shell-context-sources '(region error line files)
        agent-shell-text-file-capabilities t
        agent-shell-dot-subdir-function #'lcw-agent-state-subdirectory
        agent-shell-display-action
        `(display-buffer-in-side-window
          (side . right)
          (slot . 0)
          (window-width . ,lcw-agent-sidebar-width)
          (dedicated . t))
        ;; Following a source link should use the editing area rather than
        ;; replacing the conversation in the dedicated side window.
        agent-shell-file-display-action
        '((display-buffer-reuse-window display-buffer-use-some-window)
          (inhibit-same-window . t))))

(use-package agent-shell-tramp
  :if (locate-library "agent-shell-tramp")
  :after agent-shell
  :custom
  (agent-shell-tramp-transcript-directory
   (expand-file-name "state/agent-shell/remote-transcripts/"
                     user-emacs-directory))
  :config
  (agent-shell-tramp-mode 1))

(provide 'init-agent)
;;; init-agent.el ends here
