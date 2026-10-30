import React, { useState } from "react";
import styled from "styled-components";
import { Icon, Tooltip } from "@shopify/polaris";
import { DragHandleMinor, ChevronUpMinor, ChevronDownMinor } from "@shopify/polaris-icons";
import { t } from "../i18n";

/* Reorder by native HTML5 drag and drop (no new dependency, FRM-12), with
   up / down buttons for keyboards and touch screens, where HTML5 drag
   events do not fire. */

const Item = styled.div`
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 10px 8px;
  border-radius: 8px;
  background: ${(p) => (p.$over ? "var(--p-color-bg-surface-hover, #f1f1f1)" : "transparent")};
  border-top: 2px solid ${(p) => (p.$over ? "var(--p-color-border-emphasis, #005bd3)" : "transparent")};
  opacity: ${(p) => (p.$dragging ? 0.4 : 1)};

  & + & {
    box-shadow: 0 -1px 0 var(--p-color-border-secondary, #ebebeb);
  }
`;

const Controls = styled.div`
  flex: 0 0 auto;
  display: flex;
  align-items: center;
  gap: 2px;
  padding-top: 2px;

  button {
    appearance: none;
    border: 0;
    background: transparent;
    padding: 2px;
    border-radius: 6px;
    cursor: pointer;
    display: inline-flex;
    color: inherit;
  }

  button:disabled {
    opacity: 0.3;
    cursor: default;
  }

  button:focus-visible {
    outline: 2px solid var(--p-color-border-focus, #005bd3);
  }

  span[data-handle] {
    display: inline-flex;
    cursor: grab;
  }

  @media (max-width: 480px) {
    span[data-handle] {
      display: none;
    }
  }
`;

const Content = styled.div`
  flex: 1;
  min-width: 0;
`;

/**
 * @param items       array to render
 * @param getKey      (item) => stable key
 * @param onReorder   (fromIndex, toIndex) => void
 * @param renderItem  (item, index) => node
 * @param isLocked    (item) => true to pin an item (not draggable, not a drop target)
 */
const SortableList = ({ items, getKey, onReorder, renderItem, isLocked, header }) => {
  const [dragIndex, setDragIndex] = useState(null);
  const [overIndex, setOverIndex] = useState(null);
  const locked = (item) => (isLocked ? isLocked(item) : false);

  const reset = () => {
    setDragIndex(null);
    setOverIndex(null);
  };

  const canMove = (index, direction) => {
    const target = index + direction;
    return target >= 0 && target < items.length && !locked(items[index]) && !locked(items[target]);
  };

  return (
    <div role="list">
      {header && (
        <Item>
          <Controls aria-hidden="true" style={{ visibility: "hidden" }}>
            <span data-handle>
              <Icon source={DragHandleMinor} />
            </span>
            <button type="button" tabIndex={-1}>
              <Icon source={ChevronUpMinor} />
            </button>
            <button type="button" tabIndex={-1}>
              <Icon source={ChevronDownMinor} />
            </button>
          </Controls>
          <Content>{header}</Content>
        </Item>
      )}
      {items.map((item, index) => {
        const pinned = locked(item);
        return (
          <Item
            key={getKey(item)}
            role="listitem"
            draggable={!pinned}
            $dragging={dragIndex === index}
            $over={overIndex === index && dragIndex !== null && dragIndex !== index}
            onDragStart={(event) => {
              if (pinned) return;
              setDragIndex(index);
              if (event.dataTransfer) {
                event.dataTransfer.effectAllowed = "move";
                try {
                  event.dataTransfer.setData("text/plain", String(index));
                } catch (_) {
                  /* some browsers refuse custom data; the index lives in state */
                }
              }
            }}
            onDragOver={(event) => {
              if (dragIndex === null || pinned) return;
              event.preventDefault();
              if (overIndex !== index) setOverIndex(index);
            }}
            onDrop={(event) => {
              event.preventDefault();
              if (dragIndex !== null && !pinned && dragIndex !== index) onReorder(dragIndex, index);
              reset();
            }}
            onDragEnd={reset}
          >
            <Controls>
              {!pinned && (
                <Tooltip content={t("designer.drag_to_reorder", "Drag to reorder")}>
                  <span data-handle>
                    <Icon source={DragHandleMinor} tone="subdued" />
                  </span>
                </Tooltip>
              )}
              <button
                type="button"
                aria-label={t("designer.move_up", "Move up")}
                disabled={!canMove(index, -1)}
                onClick={() => onReorder(index, index - 1)}
              >
                <Icon source={ChevronUpMinor} tone="base" />
              </button>
              <button
                type="button"
                aria-label={t("designer.move_down", "Move down")}
                disabled={!canMove(index, 1)}
                onClick={() => onReorder(index, index + 1)}
              >
                <Icon source={ChevronDownMinor} tone="base" />
              </button>
            </Controls>
            <Content>{renderItem(item, index)}</Content>
          </Item>
        );
      })}
    </div>
  );
};

export default SortableList;
