#
# X-Plane highlight untextured
#
# Copyright (c) 2006-2013 Jonathan Harris
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#

module Marginal
  module SU2XPlane

    def self.XPlaneHighlight()

      model=Sketchup.active_model
      materials=model.materials
      model.start_operation(L10N.t('Highlight Untextured'), true)
      begin
        untextured=materials["XPUntextured"]
        if (not untextured) or (untextured.texture and untextured.texture.filename)
          untextured=materials.add("XPUntextured")
          untextured.color="Red"
        end
        untextured.alpha=1.0
        untextured.texture=nil

        reverse=materials["XPReverse"]
        if (not reverse) or (reverse.texture and reverse.texture.filename)
          reverse=materials.add("XPReverse")
          reverse.color="Magenta"
        end
        reverse.alpha=0
        reverse.texture=nil

        while !model.selection.empty? do model.selection.shift end	# clear selection
        count=XPlaneHighlightFaces(model.entities, untextured, reverse, model.selection)
        model.commit_operation
        UI.messagebox L10N.t('All faces are textured'), MB_OK,"X-Plane export" if count==0
      rescue => e
        puts "Error: #{e.inspect}", e.backtrace	# Report to console
        model.abort_operation
      end

    end


    def self.XPlaneHighlightFaces(entities, untextured, reverse, selection)

      count=0

      entities.each do |ent|

        case ent

        when Sketchup::ComponentInstance
          count+=XPlaneHighlightFaces(ent.definition.entities, untextured, reverse, selection)

        when Sketchup::Group
          count+=XPlaneHighlightFaces(ent.entities, untextured, reverse, selection)

        when Sketchup::Face
          if not (ent.material and ent.material.texture and ent.material.texture.filename) and not (ent.back_material and ent.back_material.texture and ent.back_material.texture.filename)
            ent.material=untextured
            ent.back_material=reverse
            selection.add(ent)
            count+=1
          else
            ent.material=reverse if not (ent.material and ent.material.texture and ent.material.texture.filename)
            ent.back_material=reverse if not (ent.back_material and ent.back_material.texture and ent.back_material.texture.filename)
          end

        end
      end

      return count

    end

  end
end
