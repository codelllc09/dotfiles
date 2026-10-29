;;; init-ui.el --- Frames, tabs, themes, fonts, and icons -*- lexical-binding: t; -*-

(when (fboundp 'menu-bar-mode)
  (menu-bar-mode -1))
(when (fboundp 'tool-bar-mode)
  (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode)
  (scroll-bar-mode -1))
(when (fboundp 'horizontal-scroll-bar-mode)
  (horizontal-scroll-bar-mode -1))
(column-number-mode 1)

;;; Mode line ---------------------------------------------------------------

(defgroup lcw-ui nil
  "Frame chrome, mode line, tabs, themes, and typography."
  :group 'convenience)

;; The mode line is `doom-modeline', the same building block Centaur, Doom, and
;; Spacemacs use.  It reports position, file state, encoding, and size like the
;; hand-written format did, and adds project, VC branch, checker counts, and
;; icons instead of re-implementing them here.
(defcustom lcw-mode-line-file-buffers-only nil
  "When non-nil, show the mode line only in buffers that visit a file.
Tool buffers (Agent Shell, Dired, Magit, Help, compilation, ...) then end with
a bare edge, which is how this configuration behaved before adopting
`doom-modeline'.  The default shows the mode line everywhere, like Centaur."
  :type 'boolean
  :group 'lcw-ui)

(defun lcw-mode-line--escape-percent (text)
  "Double percent signs in TEXT while preserving its text properties."
  (let ((position 0))
    (while (setq position (string-match "%" text position))
      (setq text (concat (substring text 0 position)
                         (substring text position (1+ position))
                         (substring text position))
            position (+ position 2)))
    text))

(defun lcw-ui-file-buffer-p ()
  "Return non-nil when the current buffer represents a visited file.
Indirect buffers inherit the file identity of their base buffer."
  (or buffer-file-name
      (when-let* ((base (buffer-base-buffer)))
        (buffer-local-value 'buffer-file-name base))))

(defun lcw-apply-mode-line-policy ()
  "Apply `lcw-mode-line-file-buffers-only' to the current buffer."
  (if (and lcw-mode-line-file-buffers-only
           (not (lcw-ui-file-buffer-p)))
      (setq-local mode-line-format nil)
    ;; Never pin a copy of the default value here: `doom-modeline-mode'
    ;; rewrites it when it starts, and a buffer-local copy would go stale.
    (kill-local-variable 'mode-line-format))
  (force-mode-line-update))

;; Re-evaluate when a buffer changes mode or gains a visited file name.
(add-hook 'after-change-major-mode-hook #'lcw-apply-mode-line-policy 100)
(add-hook 'find-file-hook #'lcw-apply-mode-line-policy 100)
(add-hook 'after-set-visited-file-name-hook #'lcw-apply-mode-line-policy 100)

(defun lcw-hide-noisy-mode-line-lighters ()
  "Hide redundant minor-mode labels without disabling their features."
  (dolist (mode '(which-key-mode
                  eldoc-mode))
    (when-let* ((entry (assq mode minor-mode-alist)))
      (setcdr entry '(nil)))))

(lcw-hide-noisy-mode-line-lighters)
(with-eval-after-load 'which-key
  (lcw-hide-noisy-mode-line-lighters))
(with-eval-after-load 'eldoc
  (lcw-hide-noisy-mode-line-lighters))

(defun lcw-hide-markdown-mode-name ()
  "Hide the redundant GFM major-mode label in Markdown buffers."
  (when (derived-mode-p 'markdown-mode)
    (setq-local mode-name nil)))

(add-hook 'gfm-mode-hook #'lcw-hide-markdown-mode-name 90)
;; Apply the same display change when this file is reloaded with Markdown
;; buffers already open.
(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (lcw-hide-markdown-mode-name)))

;; Restore the normal background actions in sessions that loaded the earlier
;; version of this setting.  The text-specific map above still absorbs clicks.
(keymap-global-set "<mode-line> <down-mouse-1>" #'mouse-drag-mode-line)
(keymap-global-set "<mode-line> <mouse-1>" #'mouse-select-window)
(keymap-global-set "<mode-line> <mouse-2>" #'mouse-delete-other-windows)
(keymap-global-set "<mode-line> <mouse-3>" #'mouse-delete-window)

;; Give the frame content some breathing room and keep split windows distinct.
;; The default applies to future frames; set-frame-parameter updates this one.
(add-to-list 'default-frame-alist '(vertical-scroll-bars . nil))
(add-to-list 'default-frame-alist '(horizontal-scroll-bars . nil))
(add-to-list 'default-frame-alist '(internal-border-width . 15))
(set-frame-parameter nil 'internal-border-width 15)
(setq window-divider-default-right-width 1
      window-divider-default-bottom-width 2)
(window-divider-mode 1)

(defface lcw-terminal-header-label
  '((t (:inherit header-line :foreground "#89b4fa" :weight bold)))
  "Face for the terminal panel label and working directory.")

(defface lcw-terminal-header-hint
  '((t (:inherit header-line :foreground "#6c7086")))
  "Face for the terminal panel's quiet key hint.")

(defface lcw-mode-line-file-meta
  '((t (:foreground "#6c7086")))
  "Face for the quiet directory segment of the mode line.")

(defun lcw-copy-current-file-path ()
  "Copy the current buffer's complete local or TRAMP file path."
  (interactive)
  (unless buffer-file-name
    (user-error "This buffer does not visit a file"))
  (kill-new buffer-file-name)
  (message "Copied: %s" buffer-file-name))

(defvar lcw-mode-line-path-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1] #'lcw-copy-current-file-path)
    map)
  "Mouse map that copies the file path from the mode-line directory segment.")

(defun lcw-mode-line-directory-label (file)
  "Return a short, left-truncated directory label for FILE."
  (let* ((label
          (directory-file-name
           (if-let* ((method (file-remote-p file 'method)))
               (format "%s %s%s > %s"
                       (upcase method)
                       (if-let* ((user (file-remote-p file 'user)))
                           (concat user "@")
                         "")
                       (or (file-remote-p file 'host) "remote")
                       (file-name-directory
                        (file-remote-p file 'localname)))
             (file-name-directory (abbreviate-file-name file)))))
         (limit 40))
    (if (> (length label) limit)
        (concat "..." (substring label (- (length label) (- limit 3))))
      label)))

(defun lcw-mode-line-directory ()
  "Return the clickable directory of the current file for the mode line.
The full path is shown in the tooltip and copied on mouse-1."
  (when buffer-file-name
    (let ((label (lcw-mode-line--escape-percent
                  (lcw-mode-line-directory-label buffer-file-name))))
      (propertize (concat "  " label)
                  'face 'lcw-mode-line-file-meta
                  'help-echo (concat buffer-file-name "\nmouse-1: copy path")
                  'mouse-face 'mode-line-highlight
                  'local-map lcw-mode-line-path-map))))

;; `doom-modeline' replaces the hand-written bottom line.  The layout is
;; Centaur's, plus the directory segment above so that the file identity the
;; header line used to carry stays visible.
(use-package doom-modeline
  :if (locate-library "doom-modeline")
  :custom
  (doom-modeline-height 28)
  (doom-modeline-icon t)
  (doom-modeline-major-mode-icon t)
  (doom-modeline-major-mode-color-icon t)
  (doom-modeline-buffer-state-icon t)
  (doom-modeline-buffer-modification-icon t)
  (doom-modeline-minor-modes nil)
  (doom-modeline-enable-word-count nil)
  (doom-modeline-project-name t)
  (doom-modeline-buffer-file-name-style 'truncate-with-project)
  :hook (after-init . lcw-enable-doom-modeline)
  :config
  (doom-modeline-def-segment lcw-directory (lcw-mode-line-directory))
  (doom-modeline-def-modeline 'main
    '(bar window-number matches buffer-info remote-host lcw-directory
          buffer-position selection-info)
    '(misc-info project-name lsp minor-modes buffer-encoding
      major-mode process vcs check)))

(defun lcw-enable-doom-modeline ()
  "Turn on `doom-modeline' and paint it with the current theme."
  (doom-modeline-mode 1)
  (lcw-apply-doom-modeline-faces))

(defun lcw-apply-doom-modeline-faces ()
  "Tint the mode line with the Catppuccin Mocha palette."
  ;; Theme reloads call this before `doom-modeline' is loaded, and the faces
  ;; only exist once its core is available.
  (when (require 'doom-modeline-core nil t)
    (set-face-attribute 'mode-line nil
                        :background "#181825" :foreground "#a6adc8" :box nil)
    (set-face-attribute 'mode-line-inactive nil
                        :background "#181825" :foreground "#585b70" :box nil)
    (set-face-attribute 'doom-modeline-bar nil
                        :background "#89b4fa" :foreground "#181825")
    (set-face-attribute 'doom-modeline-bar-inactive nil
                        :background "#45475a" :foreground "#181825")
    (dolist (face '(doom-modeline-buffer-path doom-modeline-buffer-file))
      (set-face-attribute face nil
                          :background "#181825" :foreground "#cdd6f4"
                          :weight 'bold))
    (set-face-attribute 'doom-modeline-buffer-modified nil
                        :background "#181825" :foreground "#f38ba8")
    (set-face-attribute 'doom-modeline-buffer-major-mode nil
                        :background "#181825" :foreground "#89b4fa")
    (set-face-attribute 'doom-modeline-project-dir nil
                        :background "#181825" :foreground "#6c7086")
    (set-face-attribute 'doom-modeline-info nil
                        :background "#181825" :foreground "#a6e3a1")
    (set-face-attribute 'doom-modeline-warning nil
                        :background "#181825" :foreground "#f9e2af")
    (set-face-attribute 'doom-modeline-urgent nil
                        :background "#181825" :foreground "#f38ba8")
    (set-face-attribute 'doom-modeline-panel nil
                        :background "#313244" :foreground "#cdd6f4")))

;;;; UI palette ---------------------------------------------------------------

;; The tab-bar colors below are hand-tuned to the loaded theme; they are NOT
;; derived from theme faces.  WHEN SWITCHING OR ADDING A THEME:
;;   1. add a branch for it in `lcw-ui-palette' below (match on the theme
;;      name, fill in the seven tokens),
;;   2. keep `lcw-apply-doom-modeline-faces' (its setq block) and the
;;      dashboard/terminal faces in `lcw-apply-ui-faces' in sync -- they
;;      are still hardcoded to Mocha,
;;   3. reload -- `lcw-load-theme' already re-runs `lcw-apply-ui-faces'.
;; Unlisted themes fall through to the catch-all branch, which currently
;; mirrors Catppuccin Mocha.

(defun lcw-ui-palette ()
  "Return color tokens for the enabled theme.
Each branch matches a regexp against `custom-enabled-themes'."
  (let ((names (mapconcat #'symbol-name custom-enabled-themes " ")))
    (cond
     ;; Catppuccin Mocha (default theme, `lcw-default-theme').
     ((string-match-p "catppuccin" names)
      (list :bar-bg "#181825"        ; mantle
            :bar-fg "#6c7086"        ; overlay0
            :pill-bg "#313244"       ; surface0
            :pill-fg "#cdd6f4"       ; text
            :accent "#7f849c"        ; overlay1
            :accent-hover "#89b4fa"  ; blue
            :modified "#f9e2af"     ; peach
            :vc-modified "#f9e2af"   ; yellow
            :vc-added "#a6e3a1"      ; green
            :vc-deleted "#f38ba8"    ; red
            :vc-untracked "#89b4fa"     ; blue
            :hl-line "#313244"           ; surface0
            :hl-line-inactive "#292c3c")) ; surface0 dimmed
     ;; Next theme family: add a branch here, e.g.
     ;; ((string-match-p "nord" names) (list :bar-bg ... :modified ...))
     (t
      ;; Fallback mirror of the Mocha branch; revisit per theme.
      (list :bar-bg "#181825" :bar-fg "#6c7086"
            :pill-bg "#313244" :pill-fg "#cdd6f4"
            :accent "#7f849c" :accent-hover "#89b4fa"
            :modified "#f9e2af"
            :vc-modified "#f9e2af" :vc-added "#a6e3a1"
            :vc-deleted "#f38ba8" :vc-untracked "#89b4fa"
            :hl-line "#313244" :hl-line-inactive "#292c3c")))))

(defun lcw-ui-color (key)
  "Convenience accessor for KEY in `lcw-ui-palette'."
  (plist-get (lcw-ui-palette) key))

(defun lcw-apply-dirvish-faces ()
  "Give Dirvish's current-line highlight a visible palette color.
Catppuccin maps `highlight' to a background barely lighter than the
buffer, which makes the selected line invisible.  Guarded with `facep'
because Dirvish may not be loaded yet."
  (let ((p (lcw-ui-palette)))
    (dolist (spec '((dirvish-hl-line . :hl-line)
                    (dirvish-hl-line-inactive . :hl-line-inactive)))
      (when (facep (car spec))
        (set-face-attribute (car spec) nil
                            :background (plist-get p (cdr spec))
                            :extend t)))))

;; Git gutter faces for Dirvish's `vc-state' attribute (referenced from
;; `dirvish-vc-state-face-alist' in init-project).  Colors follow the
;; palette via `lcw-apply-ui-faces'.
(defface lcw-vc-modified '((t :foreground "#f9e2af"))
  "Dirvish git gutter: modified, unlocked, needs-update."
  :group 'faces)
(defface lcw-vc-added '((t :foreground "#a6e3a1"))
  "Dirvish git gutter: locally added."
  :group 'faces)
(defface lcw-vc-deleted '((t :foreground "#f38ba8"))
  "Dirvish git gutter: removed, missing, conflict, needs-merge."
  :group 'faces)
(defface lcw-vc-untracked '((t :foreground "#89b4fa"))
  "Dirvish git gutter: unregistered files."
  :group 'faces)

;; A tab-bar tab is a workspace/window layout. Its icon follows the buffer that
;; represents the workspace, like the program icon in the WezTerm tab title.
(defun lcw-tab-bar-tab-buffer (tab)
  "Return the representative live buffer for TAB."
  (if (eq (car tab) 'current-tab)
      (window-buffer (selected-window))
    (let ((point-marker (alist-get 'wc-point tab)))
      (or (and (markerp point-marker) (marker-buffer point-marker))
          (seq-find #'buffer-live-p (alist-get 'wc-bl tab))
          (get-buffer (alist-get 'name tab))))))

(defun lcw-tab-bar-tab-name-format-label (name tab _index)
  "Clean up NAME: drop decoration stars, mark unsaved file buffers."
  (let ((label (string-trim name "\\*+" "\\*+")))
    (if-let* ((buffer (lcw-tab-bar-tab-buffer tab))
              ((buffer-file-name buffer))
              ((buffer-modified-p buffer)))
        (concat label
                (propertize " ●" 'face
                            `(:foreground ,(lcw-ui-color :modified))))
      label)))

(defun lcw-tab-bar-tab-name-format-icon (name tab _index)
  "Prefix TAB's NAME with an icon for its representative buffer."
  (let* ((buffer (lcw-tab-bar-tab-buffer tab))
         (icon (and buffer
                    (fboundp 'nerd-icons-icon-for-buffer)
                    (with-current-buffer buffer
                      (nerd-icons-icon-for-buffer)))))
    ;; Keep the icon's own face: the tab face appended later by
    ;; `tab-bar-tab-name-format-face' is subordinate to it, so icons stay
    ;; colored while still picking up the pill background.
    (concat (if (and (stringp icon) (not (string-empty-p icon)))
                icon
              (propertize "◇"))
            " " name)))

(defun lcw-tab-bar-tab-name-format-padding (name _tab _index)
  "Add horizontal breathing room around a tab NAME."
  (concat " " name " "))

(defun lcw-tab-bar--history-icon (icon-name fallback)
  "A solid caret for ICON-NAME; tinted, blue on hover.
FALLBACK is a plain glyph used when nerd-icons is unavailable."
  (if (fboundp 'nerd-icons-faicon)
      ;; mouse-face replaces the face on hover, so it must carry the
      ;; family/height itself or the glyph falls back to another font.
      (propertize
       (concat " "
               (nerd-icons-faicon icon-name
                                  :face `(:foreground ,(lcw-ui-color :accent))
                                  :height 0.9)
               " ")
       'mouse-face (list :family (nerd-icons-faicon-family)
                         :height 0.9
                         :foreground (lcw-ui-color :accent-hover)))
    (propertize (concat " " fallback " ")
                'face `(:foreground ,(lcw-ui-color :accent))
                'mouse-face `(:foreground ,(lcw-ui-color :accent-hover)))))

(defun lcw-tab-bar-format-history ()
  "Solid caret ‹ › buttons for tab history.
Rendered unconditionally; `tab-bar-history-mode' only decides
whether the commands have history to walk through."
  `((lcw-hist-back
     menu-item
     ,(lcw-tab-bar--history-icon "nf-fa-caret_left" "‹")
     tab-bar-history-back
     :help "Go back in tab history")
    (lcw-hist-fwd
     menu-item
     ,(lcw-tab-bar--history-icon "nf-fa-caret_right" "›")
     tab-bar-history-forward
     :help "Go forward in tab history")))

(defun lcw-apply-ui-faces ()
  "Style tabs, contextual status lines, and window boundaries.
Tab colors come from `lcw-ui-palette'; see the palette section note
about keeping the rest of this function theme-synced."
  (let* ((p (lcw-ui-palette))
         (bar-bg (plist-get p :bar-bg))
         (bar-fg (plist-get p :bar-fg))
         (pill-bg (plist-get p :pill-bg))
         (pill-fg (plist-get p :pill-fg)))
    (set-face-attribute 'tab-bar nil
                        :inherit 'default
                        :background bar-bg
                        :foreground bar-fg
                        :box nil)
    (set-face-attribute 'tab-bar-tab nil
                        :inherit 'tab-bar
                        :background pill-bg
                        :foreground pill-fg
                        :weight 'bold
                        :box `(:line-width (6 . 3) :color ,pill-bg))
    (set-face-attribute 'tab-bar-tab-inactive nil
                        :inherit 'tab-bar
                        :background bar-bg
                        :foreground bar-fg
                        :weight 'normal
                        :box `(:line-width (6 . 3) :color ,bar-bg))
    (dolist (spec '((lcw-vc-modified . :vc-modified)
                    (lcw-vc-added . :vc-added)
                    (lcw-vc-deleted . :vc-deleted)
                    (lcw-vc-untracked . :vc-untracked)))
      (set-face-attribute (car spec) nil :foreground (plist-get p (cdr spec))))
    (lcw-apply-dirvish-faces))
  ;; Only the Agent Shell / vterm panel sets a header line now.
  (set-face-attribute 'header-line nil
                      :inherit 'mode-line-inactive
                      :background "#181825"
                      :foreground "#a6adc8"
                      :box nil)
  (set-face-attribute 'lcw-terminal-header-label nil
                      :inherit 'header-line
                      :foreground "#89b4fa"
                      :weight 'bold)
  (set-face-attribute 'lcw-terminal-header-hint nil
                      :inherit 'header-line
                      :foreground "#6c7086")
  (set-face-attribute 'lcw-mode-line-file-meta nil
                      :inherit nil
                      :foreground "#6c7086")
  (dolist (face '(window-divider
                  window-divider-first-pixel
                  window-divider-last-pixel))
    (set-face-attribute face nil :foreground "#45475a"))
  (lcw-apply-doom-modeline-faces))

;; Keep the bar hidden until a second workspace exists. Unlike the default,
;; compact tabs follow their title width instead of filling the entire frame.
(use-package tab-bar
  :ensure nil
  :custom
  (tab-bar-show 1)
  (tab-bar-auto-width nil)
  (tab-bar-close-button-show nil)
  :config
  ;; Invisible gutters: plain spaces.  Only the active pill has a
  ;; background, so tinted seams just read as holes in the bar.
  (setq tab-bar-separator "  ")
  ;; Style the "+" button; raw menu-item strings inherit the plain
  ;; tab-bar face.
  (setq tab-bar-new-button
        (propertize " + " 'face `(:foreground ,(lcw-ui-color :accent))
                    'mouse-face `(:foreground ,(lcw-ui-color :accent-hover))))
  ;; Own history buttons: the built-in `tab-bar-format-history' renders
  ;; nothing when `tab-bar-history-mode' is off and leaves the arrows
  ;; unstyled in Emacs 30.
  (setq tab-bar-format
        '(lcw-tab-bar-format-history
          tab-bar-format-tabs
          tab-bar-separator
          tab-bar-format-add-tab))
  ;; label -> icon -> padding -> face: the face function runs last and
  ;; appends the active/inactive face, subordinate to the icon and
  ;; modified-dot faces.
  (setq tab-bar-tab-name-format-functions
        '(lcw-tab-bar-tab-name-format-label
          lcw-tab-bar-tab-name-format-icon
          lcw-tab-bar-tab-name-format-padding
          tab-bar-tab-name-format-face))
  (lcw-apply-ui-faces)
  (tab-bar-mode 1)
  (tab-bar-history-mode 1))

;; Buffers are selected through consult-buffer, so a persistent tab line would
;; duplicate that workflow and consume a row in every window.
(defun lcw-disable-tab-line-in-all-buffers ()
  "Disable Tab Line globally and in buffers restored from an old desktop."
  (global-tab-line-mode -1)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when tab-line-mode
        (tab-line-mode -1)))))

(use-package tab-line
  :ensure nil
  :config
  (lcw-disable-tab-line-in-all-buffers))

;; The frame has no header line of its own: file identity now lives in
;; the mode line (`lcw-mode-line-directory').  The Agent Shell / vterm
;; panel still installs a buffer-local header line for its label.


;; Curated dark-theme lineup. C-c T previews themes through consult-theme;
;; M-x lcw-load-theme switches directly.
(add-to-list 'custom-theme-load-path
             (expand-file-name "themes/github-dark/" user-emacs-directory))

(declare-function doom-themes-org-config "doom-themes-org.el")

(use-package doom-themes
  :if (locate-library "doom-themes")
  :config
  (doom-themes-org-config))

(use-package catppuccin-theme
  :if (locate-library "catppuccin-theme")
  :custom
  (catppuccin-flavor 'mocha))

(defvar lcw-default-theme 'catppuccin
  "Theme loaded at startup.
Popular picks: catppuccin, doom-one, doom-dracula, modus-vivendi,
nord, gruvbox, solarized-dark, github-dark.")

(defun lcw-load-theme (theme)
  "Disable enabled themes, then load THEME without confirmation."
  (interactive
   (list (read (completing-read "Load theme: "
                                (mapcar #'symbol-name
                                        (custom-available-themes))))))
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme t)
  (lcw-apply-ui-faces))

(cond ((memq lcw-default-theme (custom-available-themes))
       (lcw-load-theme lcw-default-theme))
      ((memq 'github-dark (custom-available-themes))
       (lcw-load-theme 'github-dark)))

;; Use an explicitly monospaced font in graphical frames, including daemon clients.
(defvar lcw-code-font-family "Maple Mono NF CN"
  "Monospaced font used for source code.")

(defun lcw-apply-code-font (&optional frame)
  "Apply the code font to graphical FRAME without changing its font size."
  (let ((frame (or frame (selected-frame))))
    (when (display-graphic-p frame)
      (when (find-font (font-spec :family lcw-code-font-family) frame)
        (set-face-attribute 'default frame :family lcw-code-font-family)
        (set-face-attribute 'fixed-pitch frame :family lcw-code-font-family)
        (dolist (script '(han kana cjk-misc bopomofo))
          (set-fontset-font t script
                            (font-spec :family lcw-code-font-family)
                            frame))))))

(add-hook 'after-make-frame-functions #'lcw-apply-code-font)
(lcw-apply-code-font)

;; Icons come from a dedicated icon font, not from the text font: Maple Mono
;; NF CN draws Nerd Font glyphs at CJK width (about two cells of ink) while
;; Emacs advances the PUA character by one cell, so the glyph spilled into the
;; single space `doom-modeline' adds after it and looked cramped next to the
;; buffer name.  The family is baked into the icon strings when this package
;; loads, so changing it needs a restart.
(use-package nerd-icons
  :if (locate-library "nerd-icons")
  :custom
  (nerd-icons-font-family "Symbols Nerd Font Mono"))

(use-package nerd-icons-dired
  :if (locate-library "nerd-icons-dired")
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package nerd-icons-corfu
  :if (locate-library "nerd-icons-corfu")
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package nerd-icons-completion
  :if (locate-library "nerd-icons-completion")
  :after marginalia
  :config
  (nerd-icons-completion-mode))

(provide 'init-ui)
;;; init-ui.el ends here
