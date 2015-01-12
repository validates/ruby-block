RubyBlockView = require './ruby-block-view'
{CompositeDisposable, Point} = require 'atom'

module.exports = RubyBlock =
  config:
    highlightBlockStartingLine:
      type: 'boolean'
      description: 'Highlight block starting line'
      default: true
    DisplayBlockStartingLineInBottomPanel:
      type: 'boolean'
      description: 'Display block starting line in bottom panel'
      default: true
    

  rubyBlockView: null
  modalPanel: null
  rubyRootScope: 'source.ruby'
  
  rubyStartBlockNames: [
    'for'
    'if'
    'unless'
    'until'
    'while'
    'class'
    'module'
    'case'
    'def'
    'begin'
  ]
  rubyStartBlockScopes: [
     'keyword.control.ruby'
     'keyword.control.start-block.ruby' 
     'keyword.control.class.ruby' 
     'keyword.control.module.ruby' 
     'keyword.control.def.ruby' 
  ]
  
  rubyEndBlockScope: 'keyword.control.ruby'
  rubyDoScope: 'keyword.control.start-block.ruby'
  rubyEndBlockName: 'end'
  
  endBlockStack: []

  activate: (state) ->
    @rubyBlockView = new RubyBlockView(state.rubyBlockViewState)
    @modalPanel = atom.workspace.addBottomPanel(item: @rubyBlockView.getElement(), visible: false)

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @activeItemSubscription = atom.workspace.onDidChangeActivePaneItem (activeItem) =>
      @modalPanel.hide() if @modalPanel.isVisible()
      @subscribeToActiveTextEditor()

    @subscribeToActiveTextEditor()              
        
    @subscriptions = new CompositeDisposable
    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-text-editor', 'ruby-block:go-to-block-starting-line': => 
      @goToBlockStartingLine()

  deactivate: ->
    @modalPanel.destroy()
    # @subscriptions.dispose()
    # @subscriptions.forEach (subscription) -> subscription.dispose()
    @activeItemSubscription.dispose()
    @cursorSubscription?.dispose()
    @rubyBlockView.destroy()

  serialize: ->
    rubyBlockViewState: @rubyBlockView.serialize()
    
  goToBlockStartingLine: ->
    return atom.boot() unless @blockStartedRowNumber?
    atom.workspace.getActiveTextEditor().setCursorBufferPosition([@blockStartedRowNumber, 0])
    
  subscribeToActiveTextEditor: ->
    @cursorSubscription?.dispose()
    
    return if atom.packages.isPackageActive('language-ruby') is false or !@getActiveTextEditor()?
    if @getActiveTextEditor().getRootScopeDescriptor().scopes[0].indexOf(@rubyRootScope) >= 0
      @cursorSubscription = @getActiveTextEditor()?.onDidChangeCursorPosition =>
        @blockStartedRowNumber = null
        @modalPanel.hide() if @modalPanel.isVisible()
        @maker?.destroy()
        @maker = @searchForBlock()
      @maker = @searchForBlock()
      

  getActiveTextEditor: ->
    atom.workspace.getActiveTextEditor()
    
  searchForBlock: ->
    editor = @getActiveTextEditor()
    grammar = editor.getGrammar()
    cursor = editor.getCursor()
    currentRowNumber = cursor.getBufferRow()
    
    # scope and word matches 'end'
    return if cursor.getScopeDescriptor().scopes.indexOf(@rubyEndBlockScope) is -1 or 
              editor.getWordUnderCursor() isnt @rubyEndBlockName
    
    @endBlockStack.push(editor.getWordUnderCursor)
    
    # iterate lines above the cursor
    for rowNumber in [cursor.getBufferRow()..0]
      continue if editor.isBufferRowCommented(rowNumber)
      
      if rowNumber is currentRowNumber
        prevWordBoundaryPos = cursor.getPreviousWordBoundaryBufferPosition()
        row = editor.getTextInBufferRange([[rowNumber, 0], prevWordBoundaryPos])
      else
        row = editor.lineTextForBufferRow(rowNumber)
        
      tokens = grammar.tokenizeLine(row).tokens
      filteredTokens = (token for token,i in tokens when !token.value.match /^\s*$/)
      
      startBlock = (token for token in filteredTokens when token.scopes.indexOf(@rubyDoScope) >= 0)
      if startBlock.length > 0
        @endBlockStack.pop()
        if @endBlockStack.length is 0
          return @highlightBlock(rowNumber)
      
      for token in filteredTokens by -1
        for scope in token.scopes
          if scope is @rubyEndBlockScope and token.value is @rubyEndBlockName
            @endBlockStack.push(scope.value)
          else if @rubyStartBlockScopes.indexOf(scope) >= 0 and
                  @rubyStartBlockNames.indexOf(token.value) >= 0
            for firstTokenScope in filteredTokens[0].scopes
              if @rubyStartBlockScopes.indexOf(firstTokenScope) >= 0 and
                 @rubyStartBlockNames.indexOf(filteredTokens[0].value) >= 0
                @endBlockStack.pop()
                break
              
            if @endBlockStack.length is 0
              return @highlightBlock(rowNumber)

  highlightBlock: (rowNumber)->
    editor = @getActiveTextEditor()
    @marker = editor.markBufferPosition([rowNumber, 0])
    for type in ['gutter', 'line']
      @blockStartedRowNumber = rowNumber
      if atom.config.get('ruby-block.highlightBlockStartingLine')
        editor.decorateMarker(@marker, {type: type, class: 'ruby-block-highlight'})
      if atom.config.get('ruby-block.DisplayBlockStartingLineInBottomPanel')
        @rubyBlockView.updateMessage(rowNumber)
        @modalPanel.show()
    
    return @marker
    
