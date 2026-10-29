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
(declare-function nerd-icons-icon-for-dir "nerd-icons.el")
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
  (dirvish-side-width 40)
  ;; Dirvish normally marks its side window `no-other-window', which makes
  ;; the standard `C-x o' skip the project tree.  Keep the side window
  ;; protected from `delete-other-windows', but include it in normal focus
  ;; traversal within the current tab.
  (dirvish-side-window-parameters
   '((no-delete-other-windows . t) (no-other-window . nil)))
  ;; A single calm path at the top and a compact item count at the bottom.
  ;; The segment functions are defined below with the rest of the styling.
  (dirvish-side-header-line-format
   '(:left (lcw-side-title) :right ()))
  (dirvish-side-mode-line-format
   '(:left (lcw-side-label) :right (index)))
  ;; Four columns per level keep nested names aligned without making the
  ;; hierarchy feel cramped.  Nerd chevrons match the file icon family.
  (dirvish-subtree-prefix "  │ ")
  (dirvish-subtree-state-style 'nerd)
  (dirvish-subtree-icon-scale-factor '(0.78 . -0.05))
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
;;   |   blue    worktree changes not staged (Y column dirty)
;;           blue, not orange: green+orange are near-identical for
;;           deuteranopes (dE 11), green+blue are far apart (dE 66-69)
;;   i   dim     ignored (!!) -- same look as before
;;   -           clean / committed
;;
;; Queries run asynchronously (like dirvish/diff-hl/magit) with a short-lived
;; per-directory cache: Dirvish fires several refresh hooks per navigation
;; and opens preview panes, so the same directory is queried repeatedly.

(defgroup lcw-dirvish nil
  "Local Dired and Dirvish tweaks."
  :group 'dired)

(defface lcw-git-mark-untracked '((t :foreground "#f38ba8"))
  "Fringe mark: file is not tracked by the repository."
  :group 'lcw-dirvish)

(defface lcw-git-mark-staged '((t :foreground "#a6e3a1"))
  "Fringe mark: changes are staged but not committed."
  :group 'lcw-dirvish)

(defface lcw-git-mark-modified '((t :foreground "#89b4fa"))
  "Fringe mark: worktree changes are not staged.
Blue rather than orange on purpose: against the green staged bar,
green/orange collapses to dE 11 under deuteranopia and protanopia,
while green/blue stays at dE 66-69."
  :group 'lcw-dirvish)

(defface lcw-git-mark-ignored '((t :foreground "#6c7086"))
  "Fringe mark: file is ignored by git."
  :group 'lcw-dirvish)

(defcustom lcw-git-mark-cache-ttl 0.5
  "Seconds a directory's git status may be reused.
Long enough to collapse the several refresh hooks Dirvish fires for one
navigation, short enough that `g' shows the effect of staging a file."
  :type 'number
  :group 'lcw-dirvish)

(defvar lcw-git-mark-cache (make-hash-table :test #'equal)
  "Directory -> (TIMESTAMP . ENTRIES), used by the refresh hooks.")

(defvar lcw-git-mark-inflight (make-hash-table :test #'equal)
  "Directory -> running process, so one query per directory is in flight.")

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

(defun lcw-git-command ()
  "Return the git argv used for status queries.
`--no-optional-locks' stops status from refreshing and writing
`.git/index', so it never competes with another git command for the
index lock."
  (list "git" "--no-optional-locks" "status" "--porcelain=v1" "-z" "--ignored"))

(defun lcw-git-parse-status (string)
  "Parse STRING from `lcw-git-command' into ((FILE . KIND) ...).
KIND is `untracked', `staged', `modified' or `ignored'."
  (let ((fields (split-string string "\0" t))
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
    (nreverse entries)))

(defun lcw-git-status-sync (dir)
  "Return git entries for DIR, or nil when DIR is remote or not a repo."
  (when (and (not (file-remote-p dir)) (executable-find "git"))
    (with-temp-buffer
      (let ((default-directory (file-name-as-directory (expand-file-name dir))))
        (when (eq 0 (apply #'process-file (car (lcw-git-command)) nil t nil
                           (cdr (lcw-git-command))))
          (lcw-git-parse-status (buffer-string)))))))

(defun lcw-git-status-sentinel (process _event)
  "Record and draw the git status PROCESS just fetched."
  (when (memq (process-status process) '(exit signal))
    (let* ((dir (process-get process 'lcw-git-dir))
           (callback (process-get process 'lcw-git-callback))
           (buffer (process-buffer process))
           (ok (and (eq (process-status process) 'exit)
                    (zerop (process-exit-status process))))
           entries)
      (when (and ok (buffer-live-p buffer))
        (with-current-buffer buffer
          (setq entries (lcw-git-parse-status (buffer-string)))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (remhash dir lcw-git-mark-inflight)
      (when entries
        (puthash dir (cons (float-time) entries) lcw-git-mark-cache)
        (ignore-errors (funcall callback entries))))))

(defun lcw-git-status-async (dir callback)
  "Query git status for DIR and call CALLBACK with the entries.
Entries are also put in `lcw-git-mark-cache'.  Duplicate concurrent
queries for the same DIR are dropped."
  (cond
   ((gethash dir lcw-git-mark-inflight) nil)
   ((or (file-remote-p dir) (not (executable-find "git"))) nil)
   (t
    (let* ((default-directory (file-name-as-directory (expand-file-name dir)))
           (buffer (generate-new-buffer " *lcw-git-status*"))
           (proc
            (make-process
             :name "lcw-git-status"
             :buffer buffer
             :connection-type 'pipe
             :noquery t
             :command (lcw-git-command)
             :sentinel #'lcw-git-status-sentinel)))
      ;; Carry the context on the process object: the sentinel then needs no
      ;; closure of its own to resolve DIR, the output buffer, or CALLBACK.
      (process-put proc 'lcw-git-dir dir)
      (process-put proc 'lcw-git-callback callback)
      (puthash dir proc lcw-git-mark-inflight)))))

(defun lcw-git-mark-draw (entries)
  "Draw fringe marks for ENTRIES in the current Dired/Dirvish buffer."
  (mapc #'delete-overlay lcw-git-mark-overlays)
  (setq lcw-git-mark-overlays nil)
  (let ((dir default-directory))
    (dolist (entry entries)
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
                           (propertize " " 'display `(left-fringe ,bmp ,face)))
              ;; No `evaporate' here: an empty overlay (start = end) with
              ;; that flag is deleted by Emacs immediately, which silently
              ;; removed every mark.  We clear the list ourselves instead.
              (push ov lcw-git-mark-overlays))))))))

(defun lcw-git-mark-refresh (&rest _)
  "Refresh git status marks in the current Dired/Dirvish buffer.
Uses cached data when it is younger than `lcw-git-mark-cache-ttl',
draws stale data immediately, and always revalidates asynchronously."
  (when (and (derived-mode-p 'dired-mode) (display-graphic-p))
    (lcw-git-define-bitmaps)
    (let* ((buffer (current-buffer))
           (dir (expand-file-name default-directory))
           (cached (gethash dir lcw-git-mark-cache))
           (fresh (and cached
                       (< (- (float-time) (car cached))
                          lcw-git-mark-cache-ttl))))
      (when cached
        (lcw-git-mark-draw (cdr cached)))
      (unless fresh
        (lcw-git-status-async
         dir
         (lambda (entries)
           (when (buffer-live-p buffer)
             (with-current-buffer buffer
               (when (equal (expand-file-name default-directory) dir)
                 (lcw-git-mark-draw entries))))))))))

;; Reference-style project tree: the sidebar is one shade deeper than the
;; editor, with restrained monochrome icons, subtle guides, an unambiguous
;; selected row, and small top/bottom chrome.  Every remap is buffer-local, so
;; the full-frame file browser, tab bar and dashboard keep their own styling.

(defface lcw-dirvish-side-base
  '((t (:background "#181825" :foreground "#9399b2")))
  "Base face for the project tree sidebar."
  :group 'lcw-dirvish)

(defface lcw-dirvish-side-directory
  '((t (:foreground "#bac2de")))
  "Face for directories in the project tree."
  :group 'lcw-dirvish)

(defface lcw-dirvish-side-symlink
  '((t (:foreground "#cba6f7")))
  "Face for symbolic links in the project tree."
  :group 'lcw-dirvish)

(defface lcw-dirvish-side-icon
  '((t (:foreground "#7f849c")))
  "Face for monochrome project tree icons and disclosure arrows."
  :group 'lcw-dirvish)

(defface lcw-dirvish-side-guide
  '((t (:foreground "#313244")))
  "Face for the subtle vertical guides in expanded directories."
  :group 'lcw-dirvish)

(defface lcw-dirvish-side-selection
  '((t (:background "#313244" :foreground "#bac2de" :extend t)))
  "Face for the selected project tree row."
  :group 'lcw-dirvish)

(defface lcw-dirvish-side-selection-inactive
  '((t (:background "#1e1e2e" :foreground "#9399b2" :extend t)))
  "Face for the selected row while the project tree is unfocused."
  :group 'lcw-dirvish)

(defface lcw-dirvish-side-header
  '((t (:background "#11111b" :foreground "#bac2de"
         :box (:line-width (1 . 5) :color "#11111b"))))
  "Face for the project tree header."
  :group 'lcw-dirvish)

(defface lcw-dirvish-side-header-icon
  '((t (:foreground "#89b4fa")))
  "Face for the repository/folder icon in the project tree header."
  :group 'lcw-dirvish)

(defface lcw-dirvish-side-mode-line
  '((t (:background "#11111b" :foreground "#6c7086"
         :box (:line-width (1 . 3) :color "#11111b"))))
  "Face for the compact project tree footer."
  :group 'lcw-dirvish)

(defface lcw-dirvish-side-focus
  '((t (:inherit lcw-dirvish-side-mode-line
         :foreground "#89b4fa" :weight bold)))
  "Face for the project tree footer while its window is selected."
  :group 'lcw-dirvish)

(defun lcw-dirvish-side-short-path (directory)
  "Return a compact, tail-preserving label for DIRECTORY."
  (let* ((path (directory-file-name (abbreviate-file-name directory)))
         (limit 31)
         (tail-width (1- limit)))
    (if (<= (string-width path) limit)
        path
      (concat "…"
              (truncate-string-to-width
               path (string-width path)
               (- (string-width path) tail-width))))))

(defun dirvish-lcw-side-title-ml ()
  "Return the icon and root path shown in the project tree header."
  (let* ((root (expand-file-name default-directory))
         (icon (if (fboundp 'nerd-icons-icon-for-dir)
                   (nerd-icons-icon-for-dir
                    root :face 'lcw-dirvish-side-header-icon
                    :height 0.92 :v-adjust -0.03)
                 (propertize "▣" 'face 'lcw-dirvish-side-header-icon)))
         (label (lcw-dirvish-side-short-path root)))
    (propertize (format "  %s  %s" icon label)
                'face 'lcw-dirvish-side-header
                'help-echo root)))

(defun dirvish-lcw-side-label-ml ()
  "Return a section label that also makes sidebar focus explicit."
  (if (mode-line-window-selected-p)
      (propertize "  ● EXPLORER" 'face 'lcw-dirvish-side-focus)
    (propertize "  EXPLORER" 'face 'lcw-dirvish-side-mode-line)))

(defvar-local lcw-dirvish-side-face-cookies nil
  "Face remapping cookies installed in a Dirvish side buffer.")

(defun lcw-dirvish-side-clear-faces ()
  "Remove project tree face remappings from the current buffer."
  (mapc #'face-remap-remove-relative lcw-dirvish-side-face-cookies)
  (setq lcw-dirvish-side-face-cookies nil))

(defun lcw-dirvish-side-apply-faces ()
  "Install theme-stable, buffer-local faces for a Dirvish side buffer."
  (lcw-dirvish-side-clear-faces)
  (setq lcw-dirvish-side-face-cookies
        (list
         ;; The relative remap retains the configured Maple Mono family.  A
         ;; raw `face-remapping-alist' entry would replace and lose it.
         (face-remap-add-relative 'default 'lcw-dirvish-side-base)
         (face-remap-add-relative 'dired-directory
                                  'lcw-dirvish-side-directory)
         (face-remap-add-relative 'dired-symlink 'lcw-dirvish-side-symlink)
         (face-remap-add-relative 'dirvish-subtree-state
                                  'lcw-dirvish-side-icon)
         (face-remap-add-relative 'dirvish-subtree-guide
                                  'lcw-dirvish-side-guide)
         (face-remap-add-relative 'dirvish-hl-line
                                  'lcw-dirvish-side-selection)
         (face-remap-add-relative 'dirvish-hl-line-inactive
                                  'lcw-dirvish-side-selection-inactive)
         (face-remap-add-relative 'header-line 'lcw-dirvish-side-header)
         (face-remap-add-relative 'mode-line-inactive
                                  'lcw-dirvish-side-mode-line))))

(defun lcw-dirvish-tree-style (&rest _)
  "Apply the dedicated presentation when this is a Dirvish side buffer."
  (if (eq 'side (ignore-errors (dv-type (dirvish-curr))))
      (progn
        (setq-local nerd-icons-color-icons nil
                    dirvish-nerd-icons-palette 'lcw-dirvish-side-icon
                    line-spacing 4)
        (display-line-numbers-mode -1)
        (lcw-dirvish-side-apply-faces)
        ;; One character of left breathing room keeps icons and Git fringe
        ;; marks from feeling glued to the edge of the frame.
        (when-let ((window (get-buffer-window (current-buffer) t)))
          (set-window-margins window 1 0)))
    ;; A Dired buffer can later be reused by a normal/full-frame session.
    (lcw-dirvish-side-clear-faces)
    (kill-local-variable 'nerd-icons-color-icons)
    (kill-local-variable 'dirvish-nerd-icons-palette)
    (kill-local-variable 'line-spacing)))

(with-eval-after-load 'dirvish
  (add-hook 'dirvish-setup-hook #'lcw-dirvish-tree-style))

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
