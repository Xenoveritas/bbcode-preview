path = require 'path'
fs = require 'fs-plus'
temp = require 'temp'
wrench = require 'wrench'
BBCodePreviewView = require '../lib/bbcode-preview-view'

describe "BBCode preview package", ->
  [workspaceElement, preview] = []

  beforeEach ->
    fixturesPath = path.join(__dirname, 'fixtures')
    tempPath = temp.mkdirSync('atom')
    wrench.copyDirSyncRecursive(fixturesPath, tempPath, forceDelete: true)
    atom.project.setPaths([tempPath])

    jasmine.useRealClock()

    workspaceElement = atom.views.getView(atom.workspace)
    jasmine.attachToDOM(workspaceElement)

    waitsForPromise ->
      atom.packages.activatePackage("bbcode-preview")

    waitsForPromise ->
      atom.packages.activatePackage('language-gfm')

  expectPreviewInSplitPane = ->
    waitsFor -> atom.workspace.getCenter().getPanes().length is 2

    waitsFor "bbcode preview to be created", ->
      preview = atom.workspace.getCenter().getPanes()[1].getActiveItem()

    runs ->
      expect(preview).toBeInstanceOf(BBCodePreviewView)
      expect(preview.getPath()).toBe atom.workspace.getActivePaneItem().getPath()

  describe "when a preview has not been created for the file", ->
    it "displays a bbcode preview in a split pane", ->
      waitsForPromise -> atom.workspace.open("subdir/file.txt")
      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expectPreviewInSplitPane()

      runs ->
        [editorPane] = atom.workspace.getCenter().getPanes()
        expect(editorPane.getItems()).toHaveLength 1
        expect(editorPane.isActive()).toBe true

    describe "when the editor's path does not exist", ->
      it "splits the current pane to the right with a bbcode preview for the file", ->
        waitsForPromise -> atom.workspace.open("new.bbcode")
        runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
        expectPreviewInSplitPane()

    describe "when the editor does not have a path", ->
      it "splits the current pane to the right with a bbcode preview for the file", ->
        waitsForPromise -> atom.workspace.open("")
        runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
        expectPreviewInSplitPane()

    describe "when the path contains a space", ->
      it "renders the preview", ->
        waitsForPromise -> atom.workspace.open("subdir/file with space.md")
        runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
        expectPreviewInSplitPane()

    describe "when the path contains accented characters", ->
      it "renders the preview", ->
        waitsForPromise -> atom.workspace.open("subdir/áccéntéd.md")
        runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
        expectPreviewInSplitPane()

  describe "when a preview has been created for the file", ->
    beforeEach ->
      waitsForPromise -> atom.workspace.open("subdir/file.bbcode")
      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expectPreviewInSplitPane()

    it "closes the existing preview when toggle is triggered a second time on the editor", ->
      atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'

      [editorPane, previewPane] = atom.workspace.getCenter().getPanes()
      expect(editorPane.isActive()).toBe true
      expect(previewPane.getActiveItem()).toBeUndefined()

    it "closes the existing preview when toggle is triggered on it and it has focus", ->
      [editorPane, previewPane] = atom.workspace.getCenter().getPanes()
      previewPane.activate()

      atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expect(previewPane.getActiveItem()).toBeUndefined()

    describe "when the editor is modified", ->
      it "re-renders the preview", ->
        spyOn(preview, 'showLoading')

        bbcodeEditor = atom.workspace.getActiveTextEditor()
        bbcodeEditor.setText "Hey!"

        waitsFor ->
          preview.element.textContent.includes('Hey!')

        runs ->
          expect(preview.showLoading).not.toHaveBeenCalled()

      it "invokes ::onDidChangeBBCode listeners", ->
        bbcodeEditor = atom.workspace.getActiveTextEditor()
        preview.onDidChangeBBCode(listener = jasmine.createSpy('didChangeBBCodeListener'))

        runs ->
          bbcodeEditor.setText("Hey!")

        waitsFor "::onDidChangeBBCode handler to be called", ->
          listener.callCount > 0

      describe "when the preview is in the active pane but is not the active item", ->
        it "re-renders the preview but does not make it active", ->
          bbcodeEditor = atom.workspace.getActiveTextEditor()
          previewPane = atom.workspace.getCenter().getPanes()[1]
          previewPane.activate()

          waitsForPromise ->
            atom.workspace.open()

          runs ->
            bbcodeEditor.setText("Hey!")

          waitsFor ->
            preview.element.textContent.includes("Hey!")

          runs ->
            expect(previewPane.isActive()).toBe true
            expect(previewPane.getActiveItem()).not.toBe preview

      describe "when the preview is not the active item and not in the active pane", ->
        it "re-renders the preview and makes it active", ->
          bbcodeEditor = atom.workspace.getActiveTextEditor()
          [editorPane, previewPane] = atom.workspace.getCenter().getPanes()
          previewPane.splitRight(copyActiveItem: true)
          previewPane.activate()

          waitsForPromise ->
            atom.workspace.open()

          runs ->
            editorPane.activate()
            bbcodeEditor.setText("Hey!")

          waitsFor ->
            preview.element.textContent.includes('Hey!')

          runs ->
            expect(editorPane.isActive()).toBe true
            expect(previewPane.getActiveItem()).toBe preview

      describe "when the liveUpdate config is set to false", ->
        it "only re-renders the bbcode when the editor is saved, not when the contents are modified", ->
          atom.config.set 'bbcode-preview.liveUpdate', false

          didStopChangingHandler = jasmine.createSpy('didStopChangingHandler')
          atom.workspace.getActiveTextEditor().getBuffer().onDidStopChanging didStopChangingHandler
          atom.workspace.getActiveTextEditor().setText('ch ch changes')

          waitsFor ->
            didStopChangingHandler.callCount > 0

          runs ->
            expect(preview.element.textContent).not.toMatch("ch ch changes")
            atom.workspace.getActiveTextEditor().save()

          waitsFor ->
            preview.element.textContent.includes("ch ch changes")

    describe "when the original preview is split", ->
      it "renders another preview in the new split pane", ->
        atom.workspace.getCenter().getPanes()[1].splitRight({copyActiveItem: true})

        expect(atom.workspace.getCenter().getPanes()).toHaveLength 3

        waitsFor "split markdown preview to be created", ->
          preview = atom.workspace.getCenter().getPanes()[2].getActiveItem()

        runs ->
          expect(preview).toBeInstanceOf(MarkdownPreviewView)
          expect(preview.getPath()).toBe atom.workspace.getActivePaneItem().getPath()

    describe "when the editor is destroyed", ->
      beforeEach ->
        atom.workspace.getCenter().getPanes()[0].destroyActiveItem()

      it "falls back to using the file path", ->
        atom.workspace.getCenter().getPanes()[1].activate()
        expect(preview.file.getPath()).toBe atom.workspace.getActivePaneItem().getPath()

      it "continues to update the preview if the file is changed on #win32 and #darwin", ->
        titleChangedCallback = jasmine.createSpy('titleChangedCallback')

        runs ->
          expect(preview.getTitle()).toBe 'file.markdown Preview'
          preview.onDidChangeTitle(titleChangedCallback)
          fs.renameSync(preview.getPath(), path.join(path.dirname(preview.getPath()), 'file2.md'))

        waitsFor "title to update", ->
          preview.getTitle() is "file2.md Preview"

        runs ->
          expect(titleChangedCallback).toHaveBeenCalled()

        spyOn(preview, 'showLoading')

        runs ->
          fs.writeFileSync(preview.getPath(), "Hey!")

        waitsFor "contents to update", ->
          preview.element.textContent.includes('Hey!')

        runs ->
          expect(preview.showLoading).not.toHaveBeenCalled()

        preview.onDidChangeMarkdown(listener = jasmine.createSpy('didChangeMarkdownListener'))

        runs ->
          fs.writeFileSync(preview.getPath(), "Hey!")

        waitsFor "::onDidChangeMarkdown handler to be called", ->
          listener.callCount > 0

      it "allows a new split pane of the preview to be created", ->
        atom.workspace.getCenter().getPanes()[1].splitRight({copyActiveItem: true})

        expect(atom.workspace.getCenter().getPanes()).toHaveLength 3

        waitsFor "split markdown preview to be created", ->
          preview = atom.workspace.getCenter().getPanes()[2].getActiveItem()

        runs ->
          expect(preview).toBeInstanceOf(MarkdownPreviewView)
          expect(preview.getPath()).toBe atom.workspace.getActivePaneItem().getPath()

    describe "when a new grammar is loaded", ->
      it "re-renders the preview", ->
        atom.workspace.getActiveTextEditor().setText """
          ```javascript
          var x = y;
          ```
        """

        waitsFor "bbcode to be rendered after its text changed", ->
          preview.element.querySelector("atom-text-editor").dataset.grammar is "text plain null-grammar"

        grammarAdded = false
        runs ->
          atom.grammars.onDidAddGrammar -> grammarAdded = true

        waitsForPromise ->
          expect(atom.packages.isPackageActive('language-javascript')).toBe false
          atom.packages.activatePackage('language-javascript')

        waitsFor "grammar to be added", -> grammarAdded

        waitsFor "bbcode to be rendered after grammar was added", ->
          preview.element.querySelector("atom-text-editor").dataset.grammar isnt "source js"

  describe "when the bbcode preview view is requested by file URI", ->
    it "opens a preview editor and watches the file for changes", ->
      waitsForPromise "atom.workspace.open promise to be resolved", ->
        atom.workspace.open("bbcode-preview://#{atom.project.getDirectories()[0].resolve('subdir/file.bbcode')}")

      runs ->
        preview = atom.workspace.getActivePaneItem()
        expect(preview).toBeInstanceOf(BBCodePreviewView)

        spyOn(preview, 'renderBBCodeText')
        preview.file.emitter.emit('did-change')

      waitsFor "bbcode to be re-rendered after file changed", ->
        preview.renderBBCodeText.callCount > 0

  describe "when the editor's grammar it not enabled for preview", ->
    it "does not open the bbcode preview", ->
      atom.config.set('bbcode-preview.grammars', [])

      waitsForPromise ->
        atom.workspace.open("subdir/file.txt")

      runs ->
        spyOn(atom.workspace, 'open').andCallThrough()
        atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
        expect(atom.workspace.open).not.toHaveBeenCalled()

  describe "when the editor's path changes on #win32 and #darwin", ->
    it "updates the preview's title", ->
      titleChangedCallback = jasmine.createSpy('titleChangedCallback')

      waitsForPromise -> atom.workspace.open("subdir/file.bbcode")
      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'

      expectPreviewInSplitPane()

      runs ->
        expect(preview.getTitle()).toBe 'file.bbcode Preview'
        preview.onDidChangeTitle(titleChangedCallback)
        fs.renameSync(atom.workspace.getActiveTextEditor().getPath(), path.join(path.dirname(atom.workspace.getActiveTextEditor().getPath()), 'file2.md'))

      waitsFor ->
        preview.getTitle() is "file2.md Preview"

      runs ->
        expect(titleChangedCallback).toHaveBeenCalled()

  describe "when the URI opened does not have a bbcode-preview protocol", ->
    it "does not throw an error trying to decode the URI (regression)", ->
      waitsForPromise ->
        atom.workspace.open('%')

      runs ->
        expect(atom.workspace.getActiveTextEditor()).toBeTruthy()

  describe "when bbcode-preview:copy-html is triggered", ->
    it "copies the HTML to the clipboard", ->
      waitsForPromise ->
        atom.workspace.open("subdir/simple.txt")

      runs ->
        atom.commands.dispatch workspaceElement, 'bbcode-preview:copy-html'
        expect(atom.clipboard.read()).toBe """
          <p><i>italic</i></p>

          <p><b>bold</b></p>

          <p>encoding \u2192 issue</p>
        """

        atom.workspace.getActiveTextEditor().setSelectedBufferRange [[0, 0], [1, 0]]
        atom.commands.dispatch workspaceElement, 'bbcode-preview:copy-html'
        expect(atom.clipboard.read()).toBe """
          <p><i>italic</i></p>
        """

    describe "code block tokenization", ->
      preview = null

      beforeEach ->
        waitsForPromise ->
          atom.packages.activatePackage('language-ruby')

        waitsForPromise ->
          atom.packages.activatePackage('bbcode-preview')

        waitsForPromise ->
          atom.workspace.open("subdir/file.bbcode")

        runs ->
          workspaceElement = atom.views.getView(atom.workspace)
          atom.commands.dispatch workspaceElement, 'bbcode-preview:copy-html'
          preview = document.createElement('div')
          preview.innerHTML = atom.clipboard.read()

      describe "when the code block's fence name has a matching grammar", ->
        it "tokenizes the code block with the grammar", ->
          expect(preview.querySelector("pre span.entity.name.function.ruby")).toBeDefined()

      describe "when the code block's fence name doesn't have a matching grammar", ->
        it "does not tokenize the code block", ->
          expect(preview.querySelectorAll("pre.lang-kombucha .line .syntax--null-grammar").length).toBe 2

      describe "when the code block contains empty lines", ->
        it "doesn't remove the empty lines", ->
          expect(preview.querySelector("pre.lang-python").children.length).toBe 6
          expect(preview.querySelector("pre.lang-python div:nth-child(2)").textContent.trim()).toBe ''
          expect(preview.querySelector("pre.lang-python div:nth-child(4)").textContent.trim()).toBe ''
          expect(preview.querySelector("pre.lang-python div:nth-child(5)").textContent.trim()).toBe ''

      describe "when the code block is nested in a list", ->
        it "detects and styles the block", ->
          expect(preview.querySelector("pre.lang-javascript")).toHaveClass 'editor-colors'

  describe "sanitization", ->
    it "removes script tags and attributes that commonly contain inline scripts", ->
      waitsForPromise -> atom.workspace.open("subdir/evil.md")
      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expectPreviewInSplitPane()

      runs ->
        expect(preview[0].innerHTML).toBe """
          <p>hello<br>
          &lt;script src="index.js"&gt;&lt;/script&gt;<br>
          &lt;script&gt;alert('rm -fr')&lt;/script&gt;<br>
          &lt;img onload="alert('rm -rf')" onerror="alert('rm -fr')"&gt;<br>
          world</p>
        """

    it "remove the first <!doctype> tag at the beginning of the file", ->
      waitsForPromise -> atom.workspace.open("subdir/doctype-tag.md")
      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expectPreviewInSplitPane()

      runs ->
        expect(preview.element.innerHTML).toBe """
          <p>content
          &lt;!doctype html&gt;</p>
        """

  describe "when the bbcode contains an <html> tag", ->
    it "does not throw an exception", ->
      waitsForPromise -> atom.workspace.open("subdir/html-tag.md")
      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expectPreviewInSplitPane()

      runs -> expect(preview.element.innerHTML).toBe "content"

  describe "when the bbcode contains a <pre> tag", ->
    it "does not throw an exception", ->
      waitsForPromise -> atom.workspace.open("subdir/pre-tag.md")
      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expectPreviewInSplitPane()

      runs -> expect(preview.element.querySelector('atom-text-editor')).toBeDefined()

  describe "when there is an image with a relative path and no directory", ->
    it "does not alter the image src", ->
      atom.project.removePath(projectPath) for projectPath in atom.project.getPaths()

      filePath = path.join(temp.mkdirSync('atom'), 'bar.md')
      fs.writeFileSync(filePath, "![rel path](/foo.png)")

      waitsForPromise ->
        atom.workspace.open(filePath)

      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expectPreviewInSplitPane()

      runs ->
        expect(preview.element.innerHTML).toBe """
          <p><img src="/foo.png" alt="rel path"></p>
        """

  describe "GitHub style bbcode preview", ->
    beforeEach ->
      atom.config.set 'bbcode-preview.useGitHubStyle', false

    it "renders bbcode using the default style when GitHub styling is disabled", ->
      waitsForPromise -> atom.workspace.open("subdir/simple.md")
      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expectPreviewInSplitPane()

      runs -> expect(preview.element.getAttribute('data-use-github-style')).toBeNull()

    it "renders bbcode using the GitHub styling when enabled", ->
      atom.config.set 'bbcode-preview.useGitHubStyle', true

      waitsForPromise -> atom.workspace.open("subdir/simple.md")
      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expectPreviewInSplitPane()

      runs -> expect(preview.element.getAttribute('data-use-github-style')).toBe ''

    it "updates the rendering style immediately when the configuration is changed", ->
      waitsForPromise -> atom.workspace.open("subdir/simple.md")
      runs -> atom.commands.dispatch workspaceElement, 'bbcode-preview:toggle'
      expectPreviewInSplitPane()

      runs ->
        expect(preview.element.getAttribute('data-use-github-style')).toBeNull()

        atom.config.set 'bbcode-preview.useGitHubStyle', true
        expect(preview.element.getAttribute('data-use-github-style')).not.toBeNull()

        atom.config.set 'bbcode-preview.useGitHubStyle', false
        expect(preview.element.getAttribute('data-use-github-style')).toBeNull()

  describe "when Save as Html is triggered", ->
    beforeEach ->
      waitsForPromise -> atom.workspace.open("subdir/simple.markdown")
      runs -> atom.commands.dispatch workspaceElement, 'markdown-preview:toggle'
      expectPreviewInSplitPane()

    it "saves the HTML when it is triggered and the editor has focus", ->
      [editorPane, previewPane] = atom.workspace.getCenter().getPanes()
      editorPane.activate()

      outputPath = temp.path(suffix: '.html')
      expect(fs.isFileSync(outputPath)).toBe false

      runs ->
        spyOn(atom, 'showSaveDialogSync').andReturn(outputPath)
        atom.commands.dispatch workspaceElement, 'markdown-preview:save-as-html'

      waitsFor ->
        fs.existsSync(outputPath)

      runs ->
        expect(fs.isFileSync(outputPath)).toBe true

    it "saves the HTML when it is triggered and the preview pane has focus", ->
      [editorPane, previewPane] = atom.workspace.getCenter().getPanes()
      previewPane.activate()

      outputPath = temp.path(suffix: '.html')
      expect(fs.isFileSync(outputPath)).toBe false

      runs ->
        spyOn(atom, 'showSaveDialogSync').andReturn(outputPath)
        atom.commands.dispatch workspaceElement, 'markdown-preview:save-as-html'

      waitsFor ->
        fs.existsSync(outputPath)

      runs ->
        expect(fs.isFileSync(outputPath)).toBe true
