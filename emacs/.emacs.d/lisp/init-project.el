;;; init-project.el --- Project navigation, file browsing (Dired/Dirvish), version control (Magit/diff-hl), and session restore -*- lexical-binding: t; -*-

;; Projects use the built-in C-x p prefix. init-programming configures Eglot.
(use-package project
  :ensure nil
  :demand t
  :config
  (keymap-global-set "C-c p" project-prefix-map))

(use-package magit
  :if (locate-library "magit")
  :bind (("C-c g" . magit-status)))

(defun lcw-enable-diff-hl-maybe ()
  "Show Git line changes for local version-controlled files."
  (when (and buffer-file-name
             (not (file-remote-p buffer-file-name))
             (vc-backend buffer-file-name))
    (diff-hl-mode 1)
    (diff-hl-flydiff-mode 1)))

(use-package diff-hl
  :if (locate-library "diff-hl")
  :commands (diff-hl-mode
             diff-hl-flydiff-mode
             diff-hl-next-hunk
             diff-hl-previous-hunk
             diff-hl-stage-current-hunk
             diff-hl-revert-hunk)
  :hook (find-file . lcw-enable-diff-hl-maybe)
  :custom
  (diff-hl-disable-on-remote t)
  (diff-hl-flydiff-delay 0.5)
  :config
  (with-eval-after-load 'magit
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh)))

(keymap-global-set "C-c c" #'compile)
(keymap-global-set "C-c t" #'project-shell)
(keymap-global-set "C-c d" #'project-dired)

;; Dired uses the other visible Dired window as the default copy/move target.
(use-package dired
  :ensure nil
  :custom
  (dired-dwim-target t)
  ;; Directories first, then files, each group alphabetically.  Requires
  ;; GNU coreutils ls (fine locally and in Linux containers; BSD/macOS
  ;; remote ls would not know the flag).
  (dired-listing-switches "-alh --group-directories-first"))

;; A full-frame, multi-pane file browser with live previews lives on the
;; classic Dired key.  C-x C-f keeps the minibuffer completion workflow; a
;; prefix argument prompts for the directory first, like classic C-x d.
(defun lcw-browse-files (prompt-for-dir)
  "Browse files visually, or PROMPT-FOR-DIR like classic `dired'.
Interactively, PROMPT-FOR-DIR is the prefix argument."
  (interactive "P")
  (if prompt-for-dir
      (call-interactively #'dired)
    (dirvish default-directory)))

(defun lcw-dirvish-disable-legacy-icons ()
  "Let Dirvish be the sole icon renderer in its Dired buffer."
  (when (bound-and-true-p nerd-icons-dired-mode)
    (nerd-icons-dired-mode -1)))

;; Load the struct accessors before defining commands that update session
;; fields.  The package itself remains conditional for fresh installations.
(when (locate-library "dirvish")
  (require 'dirvish)
  ;; NonGNU ELPA 2.3 keeps dirvish-side in the extensions subdirectory
  ;; without autoloads.  The use-package form below adds that path too,
  ;; but only after this block has run, so extend `load-path' here first.
  (when-let* ((library (locate-library "dirvish"))
              (extensions (expand-file-name "extensions"
                                            (file-name-directory library))))
    (when (file-directory-p extensions)
      (add-to-list 'load-path extensions)))
  ;; The side-bar extension ships without autoloads entries, so `M-x
  ;; dirvish-side' stays invisible until it is loaded here explicitly.
  ;; `dirvish-side-follow-mode' makes the tree reveal the current file,
  ;; like the VSCode explorer sidebar.
  (require 'dirvish-side)
  (dirvish-side-follow-mode 1))

;; Compiling this file needs Dirvish loaded: `lcw-dirvish-toggle-hidden-files'
;; uses `(setf (dv-ls-switches ...))', and without the struct's setf expander
;; on the compiler side the emitted code calls a `(setf dv-ls-switches)'
;; function that cl-defstruct never defines -> void-function at runtime.
;; `batch-byte-compile' does not execute the file body, so the runtime
;; `require' block above does not help the compiler - only this does.
(eval-when-compile
  (when (locate-library "dirvish")
    (require 'dirvish)
    (when (locate-library "dirvish-side")
      (require 'dirvish-side))))
(declare-function nerd-icons-dired-mode "nerd-icons-dired.el")
(declare-function dirvish-side "dirvish-side.el")
(declare-function dirvish-side-follow-mode "dirvish-side.el")
(declare-function lcw-disable-tab-line-in-all-buffers "init-ui.el")

(defun lcw-dirvish-listing-shows-hidden-p (switches)
  "Return non-nil when ls SWITCHES include hidden files."
  (seq-some
   (lambda (switch)
     (or (member switch '("--all" "--almost-all"))
         (and (string-match-p "\\`-[^-]" switch)
              (string-match-p "[aA]" switch))))
   (split-string switches nil t)))

(defun lcw-dirvish-set-hidden-switch (switches show)
  "Return ls SWITCHES adjusted to SHOW or hide dotfiles."
  (let ((parts (split-string switches nil t)))
    (if show
        (if (lcw-dirvish-listing-shows-hidden-p switches)
            switches
          (mapconcat #'identity (cons "-A" parts) " "))
      (mapconcat
       #'identity
       (delq
        nil
        (mapcar
         (lambda (switch)
           (cond
            ((member switch '("--all" "--almost-all")) nil)
            ((string-match-p "\\`-[^-]+\\'" switch)
             (let ((trimmed
                    (replace-regexp-in-string "[aA]" "" switch)))
               (unless (equal trimmed "-") trimmed)))
            (t switch)))
         parts))
       " "))))

(defun lcw-dirvish-sync-listing-switches ()
  "Keep previews consistent with the current Dirvish session."
  (when-let ((session (dirvish-curr)))
    (setq-local dired-listing-switches (dv-ls-switches session))))

(defun lcw-dirvish-toggle-hidden-files ()
  "Toggle dotfiles throughout the current Dirvish session."
  (interactive)
  (let* ((session (or (dirvish-curr)
                      (user-error "Not in a Dirvish session")))
         (show (not (lcw-dirvish-listing-shows-hidden-p
                     (dv-ls-switches session))))
         (switches
          (lcw-dirvish-set-hidden-switch (dv-ls-switches session) show))
         (index-buffer (cdr (dv-index session)))
         (root-window (dv-root-window session)))
    (setf (dv-ls-switches session) switches)
    (dolist (root (dv-roots session))
      (when (buffer-live-p (cdr root))
        (with-current-buffer (cdr root)
          (setq-local dired-listing-switches switches)
          (dired-sort-other switches))))
    ;; Parent and preview panes cache directory contents separately.
    (clrhash (dv-parent-hash session))
    (clrhash (dv-preview-hash session))
    (when (and (buffer-live-p index-buffer) (window-live-p root-window))
      (with-selected-window root-window
        (switch-to-buffer index-buffer)
        (dirvish--build-layout session)
        (dirvish--redisplay)))
    (message "Hidden files %s" (if show "shown" "hidden"))))

(use-package dirvish
  :if (locate-library "dirvish")
  :commands dirvish
  :init
  ;; NonGNU ELPA 2.3 keeps optional features in this subdirectory without
  ;; adding it to `load-path'; newer releases do so during installation.
  (when-let* ((library (locate-library "dirvish"))
              (extensions
               (expand-file-name "extensions" (file-name-directory library))))
    (when (file-directory-p extensions)
      (add-to-list 'load-path extensions)))
  (dirvish-override-dired-mode 1)
  :bind (("C-x d" . lcw-browse-files)
         :map dirvish-mode-map
         ("h" . dired-up-directory)
         ("j" . dired-next-line)
         ("k" . dired-previous-line)
         ("l" . dired-find-file)
         ("." . lcw-dirvish-toggle-hidden-files)
         ("?" . dirvish-dispatch)
         ("TAB" . dirvish-subtree-toggle)
         ("<tab>" . dirvish-subtree-toggle)
         ("M-f" . dirvish-history-go-forward)
         ("M-b" . dirvish-history-go-backward))
  :custom
  ;; Git status is drawn by `diff-hl-dired-mode' (see the diff-hl block
  ;; above), not by Dirvish's own `vc-state' attribute: that one paints
  ;; via delayed overlays and is known to glitch (dirvish issue #1).
  (dirvish-attributes
   '(subtree-state nerd-icons collapse file-time file-size))
  ;; `dirvish-side-attributes' defaults to a snapshot of
  ;; `dirvish-attributes' taken when dirvish-side loads, which happens
  ;; before this :custom applies.  Set it explicitly, and keep only
  ;; attributes that fit the narrow tree (no time/size/collapse).
  (dirvish-side-attributes '(subtree-state nerd-icons))
  (dirvish-use-header-line 'global)
  (dirvish-mode-line-bar-image-width 0)
  :config
  (require 'dirvish-history)
  (add-hook 'dirvish-setup-hook #'lcw-dirvish-disable-legacy-icons)
  (add-hook 'dirvish-setup-hook #'lcw-dirvish-sync-listing-switches))



;;;; Dired / Dirvish git markers ---------------------------------------------

;; `vc-git' maps both "M " (staged) and " M" (unstaged) to `edited', so the
;; vc-based pipelines cannot separate them.  Read `git status --porcelain'
;; directly and draw exactly one fringe glyph per file:
;;
;;   u   red     untracked (??)
;;   |   green   staged, not yet committed (index dirty, worktree clean)
;;   |   orange  worktree changes not staged (Y column dirty)
;;   i   dim     ignored (!!) -- same look as before
;;   -           clean / committed

(defgroup lcw-dirvish nil
  "Local Dired and Dirvish tweaks."
  :group 'dired)

(defface lcw-git-mark-untracked '((t :foreground "#f38ba8"))
  "Fringe mark: file is not tracked by the repository."
  :group 'lcw-dirvish)

(defface lcw-git-mark-staged '((t :foreground "#a6e3a1"))
  "Fringe mark: changes are staged but not committed."
  :group 'lcw-dirvish)

(defface lcw-git-mark-modified '((t :foreground "#fab387"))
  "Fringe mark: worktree changes are not staged."
  :group 'lcw-dirvish)

(defface lcw-git-mark-ignored '((t :foreground "#6c7086"))
  "Fringe mark: file is ignored by git."
  :group 'lcw-dirvish)

(defvar-local lcw-git-mark-overlays nil
  "Overlays drawn by `lcw-git-mark-refresh' in this buffer.")

(defun lcw-git-define-bitmaps ()
  "Define the fringe bitmaps used by the git status marks."
  (unless (fringe-bitmap-p 'lcw-git-bmp-u)
    ;; Blocky "u": two 1px stems joined at the bottom, 3px wide.
    (define-fringe-bitmap 'lcw-git-bmp-u [5 5 5 5 5 5 7] nil 3 'center)
    ;; Solid 3px bar for staged/modified, told apart by color only.
    (define-fringe-bitmap 'lcw-git-bmp-bar [255] nil 3 '(center repeated))
    ;; Small "i" (same shape diff-hl uses for ignored entries).
    (define-fringe-bitmap 'lcw-git-bmp-i [3 3 0 3 3 3 3 3 3 3] nil 2 'center)))

(defun lcw-git-status (dir)
  "Return ((RELATIVE-NAME . KIND) ...) for DIR.
KIND is `untracked', `staged', `modified' or `ignored'."
  (when (and (not (file-remote-p dir)) (executable-find "git"))
    (with-temp-buffer
      (when (eq 0 (process-file "git" nil t nil
                                "status" "--porcelain=v1" "-z" "--ignored"))
        (let ((fields (split-string (buffer-string) "\0" t))
              entries)
          (while fields
            (let* ((entry (pop fields))
                   (xy (substring entry 0 2))
                   (path (substring entry 3)))
              ;; Renames and copies carry the original path as the next field.
              (when (memq (aref xy 0) '(?R ?C))
                (pop fields))
              (push (cons path
                          (cond ((equal xy "??") 'untracked)
                                ((equal xy "!!") 'ignored)
                                ;; Y column dirty => worktree changes remain.
                                ((not (eq (aref xy 1) ?\s)) 'modified)
                                (t 'staged)))
                    entries)))
          entries)))))

(defun lcw-git-mark-refresh (&rest _)
  "Draw git status marks in the current Dired/Dirvish buffer."
  (when (and (derived-mode-p 'dired-mode) (display-graphic-p))
    (lcw-git-define-bitmaps)
    (mapc #'delete-overlay lcw-git-mark-overlays)
    (setq lcw-git-mark-overlays nil)
    (let ((dir default-directory))
      (dolist (entry (lcw-git-status dir))
        (let* ((file (car entry))
               (kind (cdr entry))
               (face (pcase kind
                       ('untracked 'lcw-git-mark-untracked)
                       ('staged 'lcw-git-mark-staged)
                       ('modified 'lcw-git-mark-modified)
                       ('ignored 'lcw-git-mark-ignored)))
               (bmp (pcase kind
                      ('untracked 'lcw-git-bmp-u)
                      ('ignored 'lcw-git-bmp-i)
                      (_ 'lcw-git-bmp-bar))))
          (save-excursion
            (when (dired-goto-file (expand-file-name file dir))
              (let ((ov (make-overlay (line-beginning-position)
                                      (line-beginning-position))))
                (overlay-put ov 'before-string
                             (propertize " " 'display
                                         `(left-fringe ,bmp ,face)))
                (overlay-put ov 'evaporate t)
                (push ov lcw-git-mark-overlays)))))))))

(add-hook 'dired-after-readin-hook #'lcw-git-mark-refresh)
(with-eval-after-load 'dirvish
  (add-hook 'dirvish-setup-hook #'lcw-git-mark-refresh))

;; dired-subtree expanded subdirectories in place inside plain Dired
;; buffers; it served the retired left Dired panel.  Dirvish ships its own
;; subtree (TAB = dirvish-subtree-toggle), so this block stays disabled.
;; Uncomment everything below to restore.  -- retired 2026-10
;;
;; (defun lcw-dired-subtree-refresh-icons ()
;;   "Refresh Nerd Icons after a Dired subtree changes."
;;   (when (and (bound-and-true-p nerd-icons-dired-mode)
;;              (fboundp 'nerd-icons-dired--refresh))
;;     (nerd-icons-dired--refresh)))
;;
;; (defun lcw-dired-subtree-line-prefix (depth)
;;   "Return a subtle four-column tree guide repeated for DEPTH."
;;   (apply #'concat
;;          (make-list depth (propertize "│   " 'face 'shadow))))
;;
;; (use-package dired-subtree
;;   :if (locate-library "dired-subtree")
;;   :after dired
;;   :bind (:map dired-mode-map
;;               ("TAB" . dired-subtree-toggle)
;;               ("<tab>" . dired-subtree-toggle))
;;   :custom
;;   (dired-subtree-line-prefix #'lcw-dired-subtree-line-prefix)
;;   (dired-subtree-use-backgrounds nil)
;;   :config
;;   (add-hook 'dired-subtree-after-insert-hook
;;             #'lcw-dired-subtree-refresh-icons 90)
;;   (add-hook 'dired-subtree-after-remove-hook
;;             #'lcw-dired-subtree-refresh-icons 90))

;; Opt-in side panels that impose no persistent IDE layout.  File browsing
;; moved to Dirvish on C-x d (see above); the left Dired panel was retired
;; with dired-subtree in 2026-10.
(defun lcw-project-root-or-default ()
  "Return the current project root, falling back to `default-directory'."
  (if-let ((project (project-current nil)))
      (expand-file-name (project-root project))
    (expand-file-name default-directory)))

(keymap-set window-prefix-map "f" #'dirvish-side)

;; Save and restore workspaces and buffers between interactive sessions.
(defun lcw-desktop-ignore-tab-line (&rest _buffer-locals)
  "Keep Tab Line disabled when restoring an older desktop session."
  (tab-line-mode -1))

(defconst lcw-desktop-directory (expand-file-name "state/desktop/" user-emacs-directory)
  "Directory holding the session saved by `desktop'.")

(defun lcw-restore-desktop ()
  "Restore the session saved by the previous Emacs.
Startup deliberately shows the dashboard instead, so this is the explicit way
back into the last session."
  (interactive)
  (setq desktop-dirname lcw-desktop-directory)
  (unless (desktop-read lcw-desktop-directory)
    (user-error "No desktop file in %s" (abbreviate-file-name lcw-desktop-directory)))
  (lcw-desktop-enable-saving))

(defun lcw-desktop-enable-saving (&rest _)
  "Start saving the session once the session is actually in use.
`desktop' restores from its own `after-init-hook' entry and rewrites the file
on exit whenever `desktop-save-mode' is on.  Leaving the mode off until the
session is restored (or a file is visited) keeps quitting straight from the
dashboard from overwriting the previous session with an empty one."
  (unless desktop-save-mode
    (setq desktop-dirname lcw-desktop-directory)
    (desktop-save-mode 1)))

(use-package desktop
  :ensure nil
  :custom
  (desktop-path (list lcw-desktop-directory))
  (desktop-base-file-name "session")
  (desktop-base-lock-name "session.lock")
  (desktop-save t)
  (desktop-restore-eager 5)
  (desktop-restore-frames nil)
  (desktop-load-locked-desktop 'check-pid)
  :config
  ;; Tab Line is deliberately disabled in init-ui. Do not let a desktop file
  ;; restore an older buffer-local tab-line-mode state after UI setup.
  (add-to-list 'desktop-minor-mode-table '(tab-line-mode nil))
  (add-to-list 'desktop-minor-mode-handlers
               '(tab-line-mode . lcw-desktop-ignore-tab-line))
  (add-hook 'desktop-after-read-hook #'lcw-disable-tab-line-in-all-buffers)
  ;; See `lcw-desktop-enable-saving': the mode stays off during startup so that
  ;; `after-init-hook' does not restore the previous session, and it is switched
  ;; on again as soon as that session is in use.
  (unless noninteractive
    (setq desktop-dirname lcw-desktop-directory)
    (add-hook 'find-file-hook #'lcw-desktop-enable-saving 90)
    (add-hook 'dired-mode-hook #'lcw-desktop-enable-saving 90)))

(provide 'init-project)
;;; init-project.el ends here
