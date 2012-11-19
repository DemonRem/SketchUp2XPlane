#
# Fix up animations when the axes change due to:
# - Use of the "Change Axes" tool
# - Component is included into a new Group or component
#

class Sketchup::Model
  attr_accessor(:XPDoneAxesModelObservers)
end

class Sketchup::ComponentInstance
  attr_accessor(:XPSavedTransformation)
end

class XPlaneAxesAppObserver < Sketchup::AppObserver

  def initialize
    Sketchup.add_observer(self)
  end

  def onNewModel(model)
    onOpenModel(model)
  end

  def onOpenModel(model)
    # Hack! onOpenModel can be called multiple times if the user opens the model multiple times.
    # But we mustn't add multiple observers otherwise we would erroneously apply the axes fix up multiple times.
    if !model.XPDoneAxesModelObservers
      XPlaneToolsObserver.new(model)
      XPlaneSelectionObserver.new(model)
      XPlaneDefinitionsObserver.new(model)
      XPlaneModelObserver.new(model)
      model.XPDoneAxesModelObservers=true
    end
  end

end


#
# Monitor use of the "Change Axes" tool and fix up animations when the axes change
#
class XPlaneToolsObserver < Sketchup::ToolsObserver
  # Order of events when the Change Axes tool is applied:
  # onActiveToolChanged ComponentCSTool, 21126
  # onToolStateChanged  ComponentCSTool, 21126, 0
  # onToolStateChanged  ComponentCSTool, 21126, 0
  # component.transformation updated with new axes; child geometry and group/component origins shifted to compensate
  # onActiveToolChanged SelectionTool,   21022

  def initialize(model)
    @model=model
    @definition=nil	# ComponentDefinition of the component that is having its axes changed
    @model.tools.add_observer(self)
  end

  def onActiveToolChanged(tools, tool_name, tool_id)
    puts "onActiveToolChanged #{tool_name} #{tool_id} #{@model.selection.to_a}" if SU2XPlane::TraceEvents
    if !@model.valid?		# this can't happen
      @model.tools.remove_observer(self)
    elsif tool_id==21126
      # Change Axes tool
      c=@model.selection.first	# can be nil if the user is changing global axes
      if c && c.typename=='ComponentInstance' && c.XPCountFrames>0
        @definition=c.definition
        @definition.instances.each { |c| c.XPSavedTransformation=c.transformation }
        @definition.entities.each  { |c| c.XPSavedTransformation=c.transformation if c.typename=='ComponentInstance' && c.XPCountFrames>0 }
      else
        @definition=nil
      end
    elsif @definition && @definition.instances.first.XPSavedTransformation.to_a!=@definition.instances.first.transformation.to_a	# Transformation has no comparison operators
      # Change Axes tool finished and axes were changed
      @model.start_operation('Change Axes', true, false, true)	# Merge with the Change Axes tool's operation
      # replicate axes shift in stored keyframe positions for all instances
      @definition.instances.each do |c|
        shift=(@model.active_entities.include?(c) ? @model.edit_transform.inverse * c.transformation : c.transformation) * c.XPSavedTransformation.inverse
        (0...c.XPCountFrames).each do |frame|
          c.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(c.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s))).to_a)
        end
      end
      # shift immediate childrens' stored keyframe positions too
      @definition.entities.each do |c|
        if c.typename=='ComponentInstance' && c.XPCountFrames>0
          shift=c.transformation * c.XPSavedTransformation.inverse
          (0...c.XPCountFrames).each do |frame|
            c.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(c.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s))).to_a)
          end
        end
      end
      @model.commit_operation
      @definition=nil
    else
      # Some other tool, or Change Axes tool cancelled
      @definition=nil
    end
  end

  if SU2XPlane::TraceEvents
    def onToolStateChanged(tools, tool_name, tool_id, tool_state)
      puts "onToolStateChanged #{tool_name} #{tool_id} #{tool_state}"
    end
  end

end


#
# Monitor change of selection in case the selection is made into a Component or Group
#
class XPlaneSelectionObserver < Sketchup::SelectionObserver

  def initialize(model)
    @model=model
    @model.selection.add_observer(self)
  end

  def onSelectionBulkChange(selection)
    puts "onSelectionBulkChange #{selection.to_a.inspect}" if SU2XPlane::TraceEvents
    selection.each do |e|
      if e.typename=='ComponentInstance'
        # Save transformations in case the user makes this selection into a Component or Group
        e.XPSavedTransformation=e.transformation if e.XPCountFrames>0
        # Save transformations of children in case the user explodes this Component
        e.definition.entities.each { |c| c.XPSavedTransformation=c.transformation if c.typename=='ComponentInstance' && c.XPCountFrames>0 }
      elsif e.typename=='Group'
        # Save transformations of children in case the user explodes this Group
        e.entities.each { |c| c.XPSavedTransformation=c.transformation if c.typename=='ComponentInstance' && c.XPCountFrames>0 }
      end
    end
  end

end


#
# Monitor creation of new Components and Groups and fix up any animations contained in the new Component/Group
#
class XPlaneDefinitionsObserver < Sketchup::DefinitionsObserver

  def initialize(model)
    @model=model
    @model.definitions.add_observer(self)
  end

  def onComponentAdded(definitions, definition)
    puts "onComponentAdded #{definitions} #{definition}", "active:  #{@model.active_entities.to_a.inspect}", "trans:   #{@model.edit_transform.to_a.inspect}" if SU2XPlane::TraceEvents
    # adjust immediate children for axes shift
    # @model.start_operation('Make Component/Group', true, false, true)	# Don't need to do this - we're still in the middle of the operation
    definition.entities.each do |c|
      # WTF? sometimes Sketchup refuses to make the requested new Component - in which case the sub-Components are new and don't have a saved Transformation
      if c.typename=='ComponentInstance' && c.XPSavedTransformation
        puts "#{c} #{c.name}", "current: "+c.transformation.to_a.inspect, "saved:   "+c.XPSavedTransformation.to_a.inspect if SU2XPlane::TraceEvents
        shift=@model.edit_transform * c.transformation * c.XPSavedTransformation.inverse
        (0...c.XPCountFrames).each do |frame|
          puts "#{frame}: " + c.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s).inspect if SU2XPlane::TraceEvents
          c.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(c.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s))).to_a)
        end
        c.XPSavedTransformation=c.transformation	# in case the user explodes the new parent Component/Group without changing selection
      end
    end
    # @model.commit_operation
  end

  if SU2XPlane::TraceEvents
    def onComponentRemoved(definitions, definition)
      # Component has already been stripped of its entities so this is of no use
      puts "onComponentRemoved #{definitions} #{definition}", "entities:#{definition.entities.to_a.inspect}"
    end
  end

end


#
# Monitor Explode of Component or Group and fix up any animations
#
class XPlaneModelObserver < Sketchup::ModelObserver

  def initialize(model)
    model.add_observer(self)
  end

  if SU2XPlane::TraceEvents
    def onTransactionStart(model)
      puts "onTransactionStart #{model}"
    end

    def onTransactionCommit(model)
      puts "onTransactionCommit #{model}"
    end

    def onTransactionEmpty(model)
      puts "onTransactionEmpty #{model}"
    end

    def onTransactionUndo(model)
      puts "onTransactionUndo #{model}"
    end

    def onTransactionRedo(model)
      puts "onTransactionRedo #{model}"
    end
  end

  def onExplode(model)
    puts "onExplode #{model} #{model.selection.to_a}", "trans:   #{model.edit_transform.to_a.inspect}" if SU2XPlane::TraceEvents
    model.selection.each do |c|
      if c.typename=='ComponentInstance' && c.XPSavedTransformation
        model.start_operation('Explode', true, false, true)
        puts "#{c} #{c.name}", "current: "+c.transformation.to_a.inspect, "saved:   "+c.XPSavedTransformation.to_a.inspect if SU2XPlane::TraceEvents
        shift=model.edit_transform.inverse * c.transformation * c.XPSavedTransformation.inverse
        (0...c.XPCountFrames).each do |frame|
          puts "#{frame}: " + c.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s).inspect if SU2XPlane::TraceEvents
          c.set_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s, (shift * Geom::Transformation.new(c.get_attribute(SU2XPlane::ATTR_DICT, SU2XPlane::ANIM_MATRIX_+frame.to_s))).to_a)
        end
        c.XPSavedTransformation=c.transformation	# in case the user re-Groups this entity without changing selection
        model.commit_operation
      end
    end
  end

end


# Install Model observers
XPlaneAxesAppObserver.new.onOpenModel(Sketchup.active_model)	# on[Open|New]Model not sent by SketchUp on initial model - see https://developers.google.com/sketchup/docs/ourdoc/appobserver#onOpenModel