import React from "react";
import { useTranslation } from "react-i18next";
import { Stack, Text, getTheme, mergeStyleSets } from "@fluentui/react";

const theme = getTheme();
const styles = mergeStyleSets({
    container: {
        padding: "20px",
        backgroundColor: theme.palette.white,
        boxShadow: theme.effects.elevation8,
        borderRadius: "4px"
    },
    header: {
        marginBottom: "15px"
    },
    row: {
        padding: "10px",
        border: `1px solid ${theme.palette.neutralLight}`,
        borderRadius: "4px",
        marginBottom: "5px",
        cursor: "pointer",
        selectors: {
            ":hover": {
                borderColor: theme.palette.themePrimary,
                backgroundColor: theme.palette.neutralLighter
            }
        }
    },
    selectedRow: {
        borderColor: theme.palette.themePrimary,
        backgroundColor: theme.palette.neutralLighterAlt
    }
});

interface CategorySelectionProps {
    selectedCategory: string;
    onCategoryChange: (category: string) => void;
}

export const CategorySelection = ({ selectedCategory, onCategoryChange }: CategorySelectionProps) => {
    const { t } = useTranslation();
    const categories = t("labels.includeCategoryOptions", { returnObjects: true });

    return (
        <div className={styles.container}>
            <Stack tokens={{ childrenGap: 10 }}>
                <Text variant="large" className={styles.header}>
                    {t("labels.includeCategory")}
                </Text>
                {Object.entries(categories).map(([key, value]) => (
                    <div key={key} className={`${styles.row} ${selectedCategory === key ? styles.selectedRow : ""}`} onClick={() => onCategoryChange(key)}>
                        <Text>{value}</Text>
                    </div>
                ))}
            </Stack>
        </div>
    );
};

export default CategorySelection;
